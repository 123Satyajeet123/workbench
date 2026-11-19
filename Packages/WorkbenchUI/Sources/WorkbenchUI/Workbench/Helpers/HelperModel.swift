import CaptureService
import Foundation
import Observation
import WorkbenchCore

/// One helper on screen: its spec, its source, the day shown, its items, and its nudge. Every helper uses this model;
/// what differs between helpers is data in the spec and the source it reads.
@Observable
final class HelperModel {
    enum Source {
        case screen(ScreenSource)
        case whatsapp(WhatsAppSource)
        case pages(PageSource)
    }

    /// The record this model shows: its name, spec and state change when the founder renames, edits or pauses it.
    private(set) var machine: Machine
    let source: Source

    var spec: HelperSpec { machine.spec }
    var name: String { machine.name }
    var isPaused: Bool { machine.state == .paused }
    private(set) var day: WorkDay
    private(set) var items: [Item] = []
    /// The screen sessions of the shown day; empty for other sources.
    private(set) var sessions: [ScreenSession] = []
    /// For a page machine: the day's page texts on its sites, and how many were past the budget.
    private(set) var pageReading: (pages: [Activity], leftOut: Int) = ([], 0)
    private(set) var phase = ReadPhase.idle
    private(set) var problem: String?
    /// macOS blocks Workbench notifications; the nudge row offers System Settings.
    private(set) var notificationsBlocked = false
    /// A new brief being tried on past days, and how it compares with the current one.
    private(set) var trial:
        (brief: String, examples: Int?, days: [WorkDay], by: Decision.By, why: String, result: Trial)?
    private(set) var trialPhase = ReadPhase.idle
    var nudge = NudgeSchedule() {
        didSet { attempt("save the nudge") { try store.saveState(Self.json(nudge), forKey: nudgeKey) } }
    }

    /// Called after a read or a mark changed this machine's items, so the review queue can follow.
    @ObservationIgnored var itemsChanged: () -> Void = {}
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let makeModel: (ModelChoice) -> RecordedModel
    @ObservationIgnored private let notifier: Notifier
    @ObservationIgnored private var nudges: Task<Void, Never>?
    private var nudgeKey: String { "\(spec.task).nudge" }
    private var nudgedKey: String { "\(spec.task).nudged" }

    init(
        machine: Machine, source: Source, store: Store, makeModel: ((ModelChoice) -> RecordedModel)? = nil,
        notifier: Notifier = SystemNotifier()
    ) {
        self.machine = machine
        self.source = source
        self.store = store
        self.makeModel = makeModel ?? { $0.model(store: store) }
        self.notifier = notifier
        day = WorkDay(containing: store.clock())
        attempt("read the saved nudge") {
            nudge =
                try store.queries.state(forKey: nudgeKey).map {
                    try JSONDecoder().decode(NudgeSchedule.self, from: Data($0.utf8))
                } ?? NudgeSchedule()
        }
        reload()
    }

    var today: WorkDay { WorkDay(containing: store.clock()) }

    /// The record after a rename, an edit or a pause. The source stays, so a chosen chat stays chosen.
    func update(_ machine: Machine) {
        self.machine = machine
        reload()
    }

    /// The chat for a chat helper; empty for the screen.
    var scope: String {
        switch source {
        case .screen, .pages: ""
        case .whatsapp(let chat): chat.chat?.jid ?? ""
        }
    }

    /// A chat helper reads nothing until the founder chose its chat.
    var isReady: Bool {
        switch source {
        case .screen: true
        case .whatsapp(let chat): chat.chat != nil
        case .pages(let pages): !pages.sites.isEmpty
        }
    }

    /// The named sets the view and the nudge use, as far as they are known now.
    var context: [String: [String]] {
        switch source {
        case .screen, .pages: [:]
        case .whatsapp(let chat): ["members": chat.members.map(\.name)]
        }
    }

    func items(on day: WorkDay) -> [Item] {
        var found: [Item] = []
        attempt("read the items") { found = try store.queries.items(of: spec.task, day: day, scope: scope) }
        return found
    }

    /// What the helper's face shows.
    var mood: Mascot.Mood {
        if phase == .reading { return .working }
        if problem != nil { return .trouble }
        return question != nil ? .asking : .calm
    }

    /// How close the helper's latest prompt and model are to earning trust, from audit answers on held-out days.
    private(set) var trust: Certificate.Status?

    /// The item the app picked to ask about, while it is unanswered. Its answer is evidence of the helper's error rate.
    var question: Item? { items.first { $0.askedWith != nil && $0.state == .proposed } }

    /// Names in the nudge's set with no item that day.
    func missing(on day: WorkDay) -> [String] {
        guard let nudge = spec.nudge else { return [] }
        let named = Set(items(on: day).map { $0[nudge.field] })
        return (context[nudge.expected] ?? []).filter { !named.contains($0) }
    }

    func show(_ day: WorkDay) {
        self.day = day
        phase = .idle
        reload()
    }

    func reload() {
        attempt("read the day") {
            items = try store.queries.items(of: spec.task, day: day, scope: scope)
            trust = try store.queries.quality().first { $0.task == spec.task }?.heldOutAudit.status
            if case .screen(let screen) = source { sessions = try screen.sessions(on: day) }
            if case .pages(let pages) = source { pageReading = try pages.reading(on: day) }
            trial = try loadTrial()
            decisions = try store.queries.decisions(of: spec.task)
        }
    }

    /// Sends the shown day to the chosen model and stores the items that pass the checks.
    func read() async { await read(day) }

    /// Marking an item the same way again takes the mark back.
    func mark(_ item: Item, as mark: Mark) {
        guard let id = item.id else { return }
        attempt("save the mark") { try store.mark(item: id, as: item.state == mark ? .proposed : mark) }
        reload()
        itemsChanged()
    }

    func dismissProblem() { problem = nil }

    /// Runs `work` against the source and shows what fails.
    func attempt(_ step: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            problem = "Could not \(step): \(error.localizedDescription)"
        }
    }

    /// The source must allow the read before the evidence is gathered and still allow it when the items are written.
    @discardableResult
    private func read(_ day: WorkDay) async -> Bool {
        guard isReady, !isPaused, phase != .reading else { return false }
        phase = .reading
        let scope = scope
        do {
            _ = try await grant(scope)
            let evidence = try await gather(day)
            let reader = HelperReader(spec: spec, model: makeModel(try ModelChoice.saved(in: store)))
            let result = try await reader.read(day: day, scope: scope, evidence: evidence, marked: try marked())
            try store.saveReading(result, of: spec, day: day, scope: scope, grant: try await grant(scope))
            if self.day == day { reload() }
            phase = .read(kept: result.items.count, dropped: result.dropped)
            problem = nil
            itemsChanged()
            return true
        } catch {
            phase = .idle
            problem = "Could not read the day: \(error.localizedDescription)"
            return false
        }
    }

    private func grant(_ scope: String) async throws -> CaptureGrant {
        try await store.grant(for: spec.source.kind, label: scope.isEmpty ? nil : scope, at: store.clock())
    }

    private func gather(_ day: WorkDay) async throws -> EvidenceSet {
        switch source {
        case .screen(let screen): try screen.evidence(on: day)
        case .whatsapp(let chat): try await chat.evidence(on: day)
        case .pages(let pages): try pages.evidence(on: day)
        }
    }

    // MARK: Trial

    private struct SavedTrial: Codable {
        var brief: String
        var days: [String]
        var by: String?
        var why: String?
        var examples: Int?
    }

    private var trialKey: String { "\(spec.task).trial" }
    /// Most past days a trial reads: each is one model call.
    static let trialDays = 30
    /// Without marked training days, a trial reads this many recent ones.
    static let unmarkedTrialDays = 5
    /// Challengers tried within this window share the test's error budget.
    static let budgetWindow: TimeInterval = 90 * 86_400

    /// The machine's decisions, newest first.
    private(set) var decisions: [Decision] = []

    /// A change the app made by itself, such as a rollback, said once on the page.
    var notice: String?

    /// Why nothing changed after the founder asked the proposer, or nil.
    private(set) var improveNote: String?

    /// Replays `brief` on stored evidence beside the current version (research 20 §4): every training day the founder
    /// marked, newest first, so old marks carry over to the items both versions give; or, with no marks yet, recent
    /// training days. Held-out days are never read. Nothing of the live machine changes.
    func startTrial(brief: String, by: Decision.By = .person, why: String = "") async {
        await startTrial(brief: brief, examples: spec.examples, by: by, why: why)
    }

    /// A trial of a new brief and example policy together.
    func startTrial(brief: String, examples: Int?, by: Decision.By, why: String) async {
        guard let brief = brief.cleaned, isReady, trialPhase != .reading else { return }
        trialPhase = .reading
        var challenger = spec
        challenger.task = Trial.task(of: spec.task)
        challenger.brief = brief
        challenger.examples = examples
        let scope = scope
        do {
            var days = try store.queries.markedDays(of: spec.task).filter { EvalSplit($0) == .dev }
                .prefix(Self.trialDays)
            if days.isEmpty {
                let since = WorkDay(containing: store.clock()).adding(days: -14)
                days = Set(try store.queries.items(of: spec.task, since: since).map(\.day)).filter {
                    EvalSplit($0) == .dev
                }
                .sorted(by: >).prefix(Self.unmarkedTrialDays)
            }
            let reader = HelperReader(spec: challenger, model: makeModel(try ModelChoice.saved(in: store)))
            for day in days {
                _ = try await grant(scope)
                let result = try await reader.read(
                    day: day, scope: scope, evidence: try await gather(day), marked: try marked())
                try store.saveReading(result, of: challenger, day: day, scope: scope, grant: try await grant(scope))
            }
            try store.log(
                Decision(
                    at: store.clock(), task: spec.task, kind: .trial, by: by, brief: brief, parentBrief: spec.brief,
                    detail: [
                        "days": String(days.count), "why": why, "examples": Self.text(examples),
                        "parentExamples": Self.text(spec.examples),
                    ]))
            try store.saveState(
                Self.json(
                    SavedTrial(
                        brief: brief, days: days.map(\.description), by: by.rawValue, why: why, examples: examples)),
                forKey: trialKey)
            trialPhase = .idle
            reload()
            itemsChanged()
        } catch {
            trialPhase = .idle
            problem = "Could not try the new brief: \(error.localizedDescription)"
        }
    }

    /// The proposer reads the founder's marks on training days and, when it finds one clear fix, starts a trial of it.
    func improve() async {
        guard trial == nil, trialPhase != .reading else { return }
        improveNote = nil
        do {
            let marked = try store.queries.items(
                of: spec.task, since: WorkDay(containing: store.clock()).adding(days: -60))
            let improver = Improver(model: makeModel(try ModelChoice.saved(in: store)))
            let (edit, run) = try await improver.propose(spec: spec, marked: marked)
            guard let edit else {
                improveNote =
                    run == nil
                    ? "Mark at least \(Improver.minimumWrong) wrong items on training days first."
                    : "No clear fix in your marks yet."
                return
            }
            await startTrial(brief: edit.apply(to: spec.brief), by: .proposer, why: edit.why)
        } catch {
            problem = "Could not look for an improvement: \(error.localizedDescription)"
        }
    }

    /// The founder keeps the current brief: the trial's items go, and the decision is logged.
    func keepCurrent() {
        if let trial {
            attempt("log the decision") {
                try store.log(
                    Decision(
                        at: store.clock(), task: spec.task, kind: .reject, by: .person, brief: trial.brief,
                        parentBrief: spec.brief, detail: Self.counts(trial.result)))
            }
        }
        endTrial()
    }

    /// Removes the trial's items and its record; the current version stays as it is.
    func endTrial() {
        attempt("end the trial") { try store.delete(.machine(Trial.task(of: spec.task))) }
        attempt("end the trial") { try store.saveState("", forKey: trialKey) }
        reload()
        itemsChanged()
    }

    /// The trial with its marked differences in the order the founder gave the marks.
    private func loadTrial() throws -> (
        brief: String, examples: Int?, days: [WorkDay], by: Decision.By, why: String, result: Trial
    )? {
        guard let text = try store.queries.state(forKey: trialKey), !text.isEmpty else { return nil }
        let saved = try JSONDecoder().decode(SavedTrial.self, from: Data(text.utf8))
        let days = saved.days.compactMap { WorkDay($0) }
        var current: [Item] = []
        var challenger: [Item] = []
        for day in days {
            current += try store.queries.items(of: spec.task, day: day, scope: scope)
            challenger += try store.queries.items(of: Trial.task(of: spec.task), day: day, scope: scope)
        }
        let order = try store.queries.markOrder(of: (current + challenger).compactMap(\.id))
        let since = store.clock().addingTimeInterval(-Self.budgetWindow)
        let tried = try store.queries.decisions(of: spec.task).filter { $0.kind == .trial && $0.at >= since }.count
        let result = Trial(
            current: current, challenger: challenger, citation: spec.citation, markOrder: order,
            threshold: EProcess.threshold(challengers: tried))
        return (
            saved.brief, saved.examples, days, saved.by.flatMap(Decision.By.init) ?? .person, saved.why ?? "", result
        )
    }

    /// The founder's marked items of the last 60 days: the reader takes examples from them by its own rule.
    private func marked() throws -> [Item] {
        try store.queries.items(of: spec.task, since: WorkDay(containing: store.clock()).adding(days: -60))
            .filter { $0.state != .proposed }
    }

    /// Learning from marks is a trial like any change: the same brief with marked examples, judged on past days.
    func learnFromMarks() async {
        await startTrial(
            brief: spec.brief, examples: Self.exampleCount, by: .person, why: "Learn from my marked examples")
    }

    /// Research 20 §9.2 starts at three right and two wrong examples.
    static let exampleCount = 5

    static func text(_ examples: Int?) -> String { examples.map(String.init) ?? "" }

    static func counts(_ trial: Trial) -> [String: String] {
        [
            "same": String(trial.same), "better": String(trial.better), "worse": String(trial.worse),
            "verdict": trial.verdict.rawValue,
        ]
    }

    // MARK: Nudge

    /// Turning the nudge on asks macOS for permission the first time; a refusal leaves it off and says why.
    func setNudge(on: Bool) async {
        guard on else {
            nudge.isOn = false
            return
        }
        switch await notifier.authorize() {
        case .allowed:
            notificationsBlocked = false
            nudge.isOn = true
        case .blocked:
            notificationsBlocked = true
        case .failed(let reason):
            problem = "macOS refused notifications: \(reason)"
        }
    }

    /// Checks once a minute while the app runs.
    func startNudges() {
        guard spec.nudge != nil else { return }
        nudges?.cancel()
        nudges = Task { [weak self] in
            while !Task.isCancelled {
                await self?.nudgeIfDue()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Reads today and names who has no item. The day is marked first, so a failure nudges once, not every minute.
    func nudgeIfDue() async {
        let now = store.clock()
        guard let message = spec.nudge?.message, isReady, !isPaused, nudge.isOn else { return }
        let lastSent: WorkDay?
        do {
            lastSent = try store.queries.state(forKey: nudgedKey).flatMap { WorkDay($0) }
        } catch {
            problem = "Could not read the nudge: \(error.localizedDescription)"
            return
        }
        guard nudge.isDue(at: now, lastSent: lastSent) else { return }
        let today = WorkDay(containing: now)
        attempt("save the nudge") { try store.saveState(today.description, forKey: nudgedKey) }
        let body: String
        if await read(today) {
            let missing = missing(on: today)
            body =
                missing.isEmpty
                ? "Everyone has \(spec.itemsNoun) today." : "\(message) \(missing.formatted(.list(type: .and)))."
        } else {
            body = problem ?? "Could not read today."
        }
        do {
            try await notifier.post(title: name, body: body)
        } catch {
            problem = "Could not show the nudge: \(error.localizedDescription)"
        }
    }

    private static func json(_ value: some Encodable) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}

/// The machines of this Mac, one model each, built from the store's machine records. The founder adds, renames,
/// edits, pauses and deletes them here; Mochi's page holds the built-in timeline.
@Observable
final class Crew {
    private(set) var machines: [HelperModel] = []
    private(set) var problem: String?

    /// Called when any machine's items change.
    /// Called when any machine's items change. Each machine also re-checks its rollback alarm then.
    @ObservationIgnored var itemsChanged: () -> Void = {}
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let makeModel: ((ModelChoice) -> RecordedModel)?
    @ObservationIgnored private let notifier: Notifier

    init(
        store: Store, capture: CaptureService, founder: @escaping () -> String,
        makeModel: ((ModelChoice) -> RecordedModel)? = nil, notifier: Notifier = SystemNotifier()
    ) {
        self.store = store
        self.capture = capture
        self.founder = founder
        self.makeModel = makeModel
        self.notifier = notifier
        reload()
    }

    /// Mochi's timeline: the built-in timeline machine, while it exists.
    var timeline: HelperModel? { machines.first { $0.spec.task == HelperSpec.timeline.task } }

    /// The machines in the sidebar's crew: every machine but Mochi's timeline.
    var crew: [HelperModel] { machines.filter { $0 !== timeline } }

    func helper(id: Int64) -> HelperModel? { machines.first { $0.machine.id == id } }

    /// The shown name of the machine that runs a task; the task itself for one no machine runs.
    func name(ofTask task: String) -> String {
        guard let name = machines.first(where: { $0.spec.task == Trial.machineTask(of: task) })?.name else {
            return task
        }
        return Trial.isTrial(task) ? "\(name) · new brief" : name
    }

    /// Makes the tried brief the machine's own, and ends the trial. From now on its held-out audit answers are
    /// watched; see `watch`.
    func switchToTrial(_ helper: HelperModel) {
        guard let trial = helper.trial else { return }
        let parent = helper.spec
        edit(helper, brief: trial.brief, examples: trial.examples)
        attempt("log the switch") {
            try store.log(
                Decision(
                    at: store.clock(), task: helper.spec.task, kind: .promote, by: .person, brief: trial.brief,
                    parentBrief: parent.brief,
                    detail: HelperModel.counts(trial.result).merging([
                        "examples": HelperModel.text(trial.examples),
                        "parentExamples": HelperModel.text(parent.examples),
                    ]) { a, _ in a }))
        }
        helper.endTrial()
    }

    /// After a switch, the new brief's held-out audit answers feed an always-valid alarm against "wrong more than 10%
    /// of the time" (research 20 §6, step 6). When it fires, the machine goes back to the brief it came from by
    /// itself, logs why and says so: the only change the app makes without the founder.
    func watch(_ helper: HelperModel) {
        guard let switched = try? store.queries.decisions(of: helper.spec.task).first, switched.kind == .promote,
            switched.brief == helper.spec.brief,
            switched.detail["examples", default: ""] == HelperModel.text(helper.spec.examples),
            let answers = try? store.queries.auditAnswers(of: helper.spec.task, since: switched.at)
        else { return }
        let wrong = answers.filter { EvalSplit($0.day) == .heldOut }.map(\.wrong)
        let evidence = EProcess.alarm(wrong)
        guard evidence >= 1 / EProcess.level else { return }
        let name = helper.name
        let line =
            "Back to \(name)'s earlier brief: the new one was wrong on \(wrong.filter { $0 }.count) of \(wrong.count) checked items."
        edit(helper, brief: switched.parentBrief, examples: Int(switched.detail["parentExamples", default: ""]))
        attempt("log the rollback") {
            try store.log(
                Decision(
                    at: store.clock(), task: helper.spec.task, kind: .rollback, by: .alarm, brief: switched.parentBrief,
                    parentBrief: switched.brief,
                    detail: [
                        "wrong": String(wrong.filter { $0 }.count), "answers": String(wrong.count),
                        "evidence": String(format: "%.1f", evidence),
                    ]))
        }
        helper.notice = line
        let notifier = notifier
        Task { try? await notifier.post(title: name, body: line) }
    }

    func reload() {
        attempt("read the machines") {
            let records = try store.queries.machines()
            machines = try records.map { record in
                if let model = helper(id: record.id) {
                    model.update(record)
                    return model
                }
                let model = HelperModel(
                    machine: record, source: try source(for: record), store: store, makeModel: makeModel,
                    notifier: notifier)
                model.itemsChanged = { [weak self, weak model] in
                    self?.itemsChanged()
                    if let model { self?.watch(model) }
                }
                model.startNudges()
                return model
            }
        }
    }

    @discardableResult
    func create(from template: MachineTemplate, name: String) -> Int64? {
        create(spec: template.spec, template: template.spec.task, name: name.cleaned ?? template.name)
    }

    /// A machine from a whole spec, such as a teammate's: its fields, view and brief come with it.
    @discardableResult
    func create(spec: HelperSpec, template: String, name: String) -> Int64? {
        var id: Int64?
        attempt("add the machine") { id = try store.createMachine(from: spec, template: template, name: name).id }
        reload()
        return id
    }

    func rename(_ helper: HelperModel, to name: String) {
        attempt("rename \(helper.name)") { try store.rename(helper.machine, to: name) }
        reload()
    }

    func edit(_ helper: HelperModel, brief: String, examples: Int?) {
        attempt("change \(helper.name)") { try store.edit(helper.machine, brief: brief, examples: examples) }
        reload()
    }

    func edit(_ helper: HelperModel, brief: String) {
        attempt("change \(helper.name)'s brief") { try store.edit(helper.machine, brief: brief) }
        reload()
    }

    func show(_ helper: HelperModel, as view: String) {
        attempt("change \(helper.name)'s view") { try store.show(helper.machine, as: view) }
        reload()
    }

    func setPaused(_ helper: HelperModel, _ paused: Bool) {
        attempt("pause \(helper.name)") { try store.setState(helper.machine, paused ? .paused : .active) }
        reload()
    }

    /// Deletes the machine, its items and marks, and its saved settings. Its runs stay in the meter.
    func delete(_ helper: HelperModel) {
        attempt("delete \(helper.name)") { try store.setState(helper.machine, .deleted) }
        reload()
    }

    func dismissProblem() { problem = nil }

    private func source(for machine: Machine) throws -> HelperModel.Source {
        switch machine.spec.source {
        case .screenSessions: .screen(ScreenSource(store: store))
        case .pageText: .pages(try PageSource(store: store, task: machine.task))
        case .whatsappChat:
            .whatsapp(try WhatsAppSource(store: store, capture: capture, task: machine.task, founder: founder))
        }
    }

    private func attempt(_ step: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            problem = "Could not \(step): \(error.localizedDescription)"
        }
    }
}

/// A machine a person can make: a built-in spec with a default name and a line on what it does.
struct MachineTemplate: Identifiable, Hashable {
    let spec: HelperSpec
    let name: String
    /// What kind of machine it is, under its name.
    let role: String
    let detail: String

    var id: String { spec.task }

    static let team = MachineTemplate(
        spec: .team, name: "Pip", role: "Team updates",
        detail: "Reads one WhatsApp group you choose and lists each person's plans, done work and blockers.")
    static let timeline = MachineTemplate(
        spec: .timeline, name: "Timeline", role: "Day timeline",
        detail: "Turns your screen sessions into blocks of work with the words they came from.")
    static let pages = MachineTemplate(
        spec: .pages, name: "Scout", role: "Page reader",
        detail:
            "Reads the text of pages you saw on sites you name, such as your mail or LinkedIn, and lists what needs your follow-up."
    )
    static let dealIntake = MachineTemplate(
        spec: .dealIntake, name: "Deal intake", role: "Deal intake",
        detail: "Reads your mail pages and lists each inbound startup, rated hot, warm or cold by your own criteria.")
    static let founderCheck = MachineTemplate(
        spec: .founderCheck, name: "Founder check", role: "Founder check",
        detail: "Reads founders' profile pages you opened and lists their roles, companies, exits and education.")
    static let companySignals = MachineTemplate(
        spec: .companySignals, name: "Signals", role: "Company signals",
        detail: "Reads news and social pages and lists funding, hires, launches and risks of companies you follow.")
    static let all = [team, timeline, pages, dealIntake, founderCheck, companySignals]
    /// The machines every store starts with; the others are made on request or from Mochi's proposals.
    static let seeded = [team, timeline]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func of(_ machine: Machine) -> MachineTemplate? { all.first { $0.spec.task == machine.template } }
}
