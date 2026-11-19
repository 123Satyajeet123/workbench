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
    /// A new brief being tried on past days, and how it compares with the current one.
    private(set) var trial: (version: Version, days: [WorkDay], by: Decision.By, why: String, result: Trial)?
    private(set) var trialPhase = ReadPhase.idle
    var nudge = NudgeSchedule() {
        didSet { attempt("save the nudge") { try store.saveState(Self.json(nudge), forKey: nudgeKey) } }
    }
    /// Reading new lines by itself through the day, for a source whose lines keep their numbers.
    var watch = WatchSchedule() {
        didSet { attempt("save the reading hours") { try store.saveState(Self.json(watch), forKey: watchKey) } }
    }

    /// Called after a read or a mark changed this machine's items, so the review queue can follow.
    @ObservationIgnored var itemsChanged: () -> Void = {}
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let makeModel: (ModelChoice) -> RecordedModel
    /// Shared by every machine and feature: one answer to whether macOS lets Workbench notify.
    let notifications: Notifications
    @ObservationIgnored private var nudges: Task<Void, Never>?
    private var nudgeKey: String { "\(spec.task).nudge" }
    private var nudgedKey: String { "\(spec.task).nudged" }
    private var watchKey: String { "\(spec.task).watch" }
    private var watchedKey: String { "\(spec.task).watched" }

    convenience init(
        machine: Machine, source: Source, store: Store, makeModel: ((ModelChoice) -> RecordedModel)? = nil,
        notifier: Notifier = SystemNotifier()
    ) {
        self.init(
            machine: machine, source: source, store: store, makeModel: makeModel,
            notifications: Notifications(notifier: notifier))
    }

    init(
        machine: Machine, source: Source, store: Store, makeModel: ((ModelChoice) -> RecordedModel)?,
        notifications: Notifications
    ) {
        self.machine = machine
        self.source = source
        self.store = store
        self.makeModel = makeModel ?? { $0.model(store: store) }
        self.notifications = notifications
        day = WorkDay(containing: store.clock())
        attempt("read the saved nudge") {
            nudge =
                try store.queries.state(forKey: nudgeKey).map {
                    try JSONDecoder().decode(NudgeSchedule.self, from: Data($0.utf8))
                } ?? NudgeSchedule()
            watch =
                try store.queries.state(forKey: watchKey).map {
                    try JSONDecoder().decode(WatchSchedule.self, from: Data($0.utf8))
                } ?? WatchSchedule()
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
        case .whatsapp(let chat): chat.chat?.jid ?? ""  // several chats: one scope for the machine
        }
    }

    /// A chat helper reads nothing until the founder chose its chat.
    var isReady: Bool {
        switch source {
        case .screen: true
        case .whatsapp(let chat): !chat.chats.isEmpty
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
            let full = try await gather(day)
            // A reading starts where the last one stopped: earlier lines go along as context only, so nothing is
            // read twice and nothing comes back reworded.
            let last = try lastLine(read: day, scope: scope)
            var evidence = full.after(last)
            for (set, names) in try recentLabels() { evidence.context[set] = names }
            if last != nil, evidence.newLines.isEmpty {
                phase = .upToDate
                problem = nil
                return true
            }
            let reader = HelperReader(spec: spec, model: makeModel(try runner(for: Version(spec))))
            let result = try await reader.read(day: day, scope: scope, evidence: evidence, marked: try marked())
            try store.saveReading(
                result, of: spec, day: day, scope: scope, grant: try await grant(scope), replacing: last == nil)
            if let top = full.lines.map(\.id).max() {
                try store.saveState(String(top), forKey: lastLineKey(day: day, scope: scope))
            }
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

    /// For each label field, the values this machine gave in the last 30 days, most used first, so a project keeps
    /// one name across days; the model may still start a new one.
    private func recentLabels() throws -> [String: [String]] {
        let fields = spec.fields.compactMap { field -> (name: String, set: String)? in
            if case .label(let set) = field.kind { (field.name, set) } else { nil }
        }
        guard !fields.isEmpty else { return [:] }
        let recent = try store.queries.items(
            of: spec.task, since: WorkDay(containing: store.clock()).adding(days: -30)
        ).filter { $0.state != .rejected }
        return Dictionary(
            fields.map { field in
                let counts = Dictionary(recent.map { ($0[field.name], 1) }, uniquingKeysWith: +)
                    .filter { !$0.key.isEmpty }
                return (field.set, counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(50).map(\.key))
            }, uniquingKeysWith: { first, _ in first })
    }

    private func lastLineKey(day: WorkDay, scope: String) -> String { "\(spec.task).read.\(scope).\(day)" }

    /// The last line a reading of this day saw, or nil before the first reading.
    private func lastLine(read day: WorkDay, scope: String) throws -> Int64? {
        try store.queries.state(forKey: lastLineKey(day: day, scope: scope)).flatMap { Int64($0) }
    }

    /// The source must allow the read: for several chats, each one of them.
    private func grant(_ scope: String) async throws -> CaptureGrant {
        if case .whatsapp(let source) = source, source.isSeveral {
            var last: CaptureGrant?
            for chat in source.chats {
                last = try await store.grant(for: .whatsapp, label: chat.jid, at: store.clock())
            }
            if let last { return last }
        }
        return try await store.grant(for: spec.source.kind, label: scope.isEmpty ? nil : scope, at: store.clock())
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
        var runner: String?
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

    /// Replays `brief` on stored evidence beside the current version; the example policy and model stay as they are.
    func startTrial(brief: String, by: Decision.By = .person, why: String = "") async {
        var version = Version(spec)
        version.brief = brief
        await startTrial(version, by: by, why: why)
    }

    /// Replays a new version (brief, example policy and model) on stored evidence beside the current one (research
    /// 20 §4): every training day the founder marked, newest first, so old marks carry over to the items both versions
    /// give; or, with no marks yet, recent training days. Held-out days are never read. Nothing live changes.
    func startTrial(_ version: Version, by: Decision.By, why: String) async {
        guard version.brief.cleaned != nil, version != Version(spec), isReady, trialPhase != .reading else { return }
        trialPhase = .reading
        var challenger = version.apply(to: spec)
        challenger.task = Trial.task(of: spec.task)
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
            let reader = HelperReader(spec: challenger, model: makeModel(try runner(for: version)))
            for day in days {
                _ = try await grant(scope)
                let result = try await reader.read(
                    day: day, scope: scope, evidence: try await gather(day), marked: try marked())
                try store.saveReading(result, of: challenger, day: day, scope: scope, grant: try await grant(scope))
            }
            try store.log(
                Decision(
                    at: store.clock(), task: spec.task, kind: .trial, by: by, brief: version.brief,
                    parentBrief: spec.brief,
                    detail: version.detail(parent: Version(spec)).merging(["days": String(days.count), "why": why]) {
                        a, _ in a
                    }))
            try store.saveState(
                Self.json(
                    SavedTrial(
                        brief: version.brief, days: days.map(\.description), by: by.rawValue, why: why,
                        examples: version.examples, runner: version.runner)),
                forKey: trialKey)
            trialPhase = .idle
            reload()
            itemsChanged()
        } catch {
            trialPhase = .idle
            problem = "Could not try the new version: \(error.localizedDescription)"
        }
    }

    /// The model a version reads with: its own runner, else the founder's choice.
    private func runner(for version: Version) throws -> ModelChoice {
        try version.runner.flatMap(ModelChoice.with(id:)) ?? ModelChoice.saved(in: store)
    }

    /// Another model on trial: the same brief and examples, read by `choice` on past days. The days' evidence goes to
    /// that model's vendor, so this runs only on the founder's click.
    func tryModel(_ choice: ModelChoice) async {
        var version = Version(spec)
        version.runner = choice.id
        await startTrial(version, by: .person, why: "Try \(choice.title)")
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
                        at: store.clock(), task: spec.task, kind: .reject, by: .person, brief: trial.version.brief,
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
        version: Version, days: [WorkDay], by: Decision.By, why: String, result: Trial
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
        let version = Version(brief: saved.brief, examples: saved.examples, runner: saved.runner)
        return (version, days, saved.by.flatMap(Decision.By.init) ?? .person, saved.why ?? "", result)
    }

    /// The founder's marked items of the last 60 days: the reader takes examples from them by its own rule.
    private func marked() throws -> [Item] {
        try store.queries.items(of: spec.task, since: WorkDay(containing: store.clock()).adding(days: -60))
            .filter { $0.state != .proposed }
    }

    /// Learning from marks is a trial like any change: the same brief with marked examples, judged on past days.
    func learnFromMarks() async {
        var version = Version(spec)
        version.examples = Self.exampleCount
        await startTrial(version, by: .person, why: "Learn from my marked examples")
    }

    /// Research 20 §9.2 starts at three right and two wrong examples.
    static let exampleCount = 5

    static func counts(_ trial: Trial) -> [String: String] {
        [
            "same": String(trial.same), "better": String(trial.better), "worse": String(trial.worse),
            "verdict": trial.verdict.rawValue,
        ]
    }

    // MARK: Nudge

    /// Turning the nudge on asks macOS for permission the first time; while macOS blocks it, it waits and turns on
    /// once the founder allows notifications.
    func setNudge(on: Bool) async {
        guard on else {
            nudge.isOn = false
            return
        }
        await notifications.whenAllowed { [weak self] in self?.nudge.isOn = true }
    }

    /// Reading through the day alerts the founder, so it needs notifications as the nudge does.
    func setWatch(on: Bool) async {
        guard on else {
            watch.isOn = false
            return
        }
        await notifications.whenAllowed { [weak self] in self?.watch.isOn = true }
    }

    /// Reads the lines that are new since the last reading, when the reading hours say so, and tells the founder
    /// about new items whose value the spec marks bad (a blocker, for the team machine).
    func readIfDue() async {
        let now = store.clock()
        guard watch.isOn, isReady, !isPaused, phase != .reading else { return }
        let lastRead = (try? store.queries.state(forKey: watchedKey)).flatMap { $0 }.flatMap {
            try? Date($0, strategy: .iso8601)
        }
        guard watch.isDue(at: now, lastRead: lastRead) else { return }
        attempt("save the reading time") { try store.saveState(now.ISO8601Format(), forKey: watchedKey) }
        let today = WorkDay(containing: now)
        let before = Set(items(on: today).compactMap(\.id))
        guard await read(today) else { return }
        let alarming = items(on: today).filter { item in
            !before.contains(item.id ?? -1) && item.fields.values.contains { spec.tones[$0] == .bad }
        }
        guard !alarming.isEmpty else { return }
        let group: String? = if case .board(let field, _) = spec.view { field } else { nil }
        let lines = alarming.map { item in
            [group.map { item[$0] } ?? "", item[spec.title]].filter { !$0.isEmpty }.joined(separator: ": ")
        }
        do {
            try await notifications.post(title: name, body: lines.joined(separator: "\n"))
        } catch {
            problem = "Could not show the alert: \(error.localizedDescription)"
        }
    }

    /// Checks once a minute while the app runs.
    func startNudges() {
        nudges?.cancel()
        nudges = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readIfDue()
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
            try await notifications.post(title: name, body: body)
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
    let notifications: Notifications

    convenience init(
        store: Store, capture: CaptureService, founder: @escaping () -> String,
        makeModel: ((ModelChoice) -> RecordedModel)? = nil, notifier: Notifier = SystemNotifier()
    ) {
        self.init(
            store: store, capture: capture, founder: founder, makeModel: makeModel,
            notifications: Notifications(notifier: notifier))
    }

    init(
        store: Store, capture: CaptureService, founder: @escaping () -> String,
        makeModel: ((ModelChoice) -> RecordedModel)?, notifications: Notifications
    ) {
        self.store = store
        self.capture = capture
        self.founder = founder
        self.makeModel = makeModel
        self.notifications = notifications
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
        let parent = HelperModel.Version(helper.spec)
        revise(helper, to: trial.version)
        attempt("log the switch") {
            try store.log(
                Decision(
                    at: store.clock(), task: helper.spec.task, kind: .promote, by: .person, brief: trial.version.brief,
                    parentBrief: parent.brief,
                    detail: HelperModel.counts(trial.result).merging(trial.version.detail(parent: parent)) { a, _ in a }
                )
            )
        }
        helper.endTrial()
    }

    /// After a switch, the new brief's held-out audit answers feed an always-valid alarm against "wrong more than 10%
    /// of the time" (research 20 §6, step 6). When it fires, the machine goes back to the brief it came from by
    /// itself, logs why and says so: the only change the app makes without the founder.
    func watch(_ helper: HelperModel) {
        guard let decisions = try? store.queries.decisions(of: helper.spec.task) else { return }
        guard let switched = decisions.first, switched.kind == .promote,
            HelperModel.Version(decision: switched) == HelperModel.Version(helper.spec),
            let answers = try? store.queries.auditAnswers(of: helper.spec.task, since: switched.at)
        else { return warnOfDrift(helper, since: decisions.first { $0.kind != .trial }?.at ?? .distantPast) }
        let wrong = answers.filter { EvalSplit($0.day) == .heldOut }.map(\.wrong)
        let evidence = EProcess.alarm(wrong)
        guard evidence >= 1 / EProcess.level else { return }
        let name = helper.name
        let line =
            "Back to \(name)'s earlier brief: the new one was wrong on \(wrong.filter { $0 }.count) of \(wrong.count) checked items."
        revise(helper, to: HelperModel.Version(parentOf: switched))
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
        let notifications = notifications
        Task { try? await notifications.post(title: name, body: line) }
    }

    /// The same alarm on a version that has no earlier one to return to: a model can change behind its name, or the
    /// work can change. It says so once per version and changes nothing; a trial is the founder's next step.
    private func warnOfDrift(_ helper: HelperModel, since: Date) {
        guard let answers = try? store.queries.auditAnswers(of: helper.spec.task, since: since) else { return }
        let wrong = answers.filter { EvalSplit($0.day) == .heldOut }.map(\.wrong)
        guard EProcess.alarm(wrong) >= 1 / EProcess.level else { return }
        let key = "\(helper.spec.task).drift"
        let version = [helper.spec.brief, helper.spec.examples.map(String.init) ?? "", helper.spec.runner ?? ""]
            .joined(separator: "\n")
        guard (try? store.queries.state(forKey: key)) != version else { return }
        attempt("remember the warning") { try store.saveState(version, forKey: key) }
        let line =
            "\(helper.name) may have got worse: wrong on \(wrong.filter { $0 }.count) of \(wrong.count) checked items on held-out days. Try a change from your marks."
        helper.notice = line
        let notifications = notifications
        let name = helper.name
        Task { try? await notifications.post(title: name, body: line) }
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
                    notifications: notifications)
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

    func revise(_ helper: HelperModel, to version: HelperModel.Version) {
        attempt("change \(helper.name)") {
            try store.revise(
                helper.machine, brief: version.brief, examples: version.examples, runner: version.runner)
        }
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
    static let workContext = MachineTemplate(
        spec: .context, name: "Atlas", role: "Work context",
        detail:
            "Reads the work chats you choose and keeps commitments, decisions, open questions, status and roles, by project."
    )
    static let all = [team, timeline, pages, workContext, dealIntake, founderCheck, companySignals]
    /// The machines every store starts with; the others are made on request or from Mochi's proposals.
    static let seeded = [team, timeline]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func of(_ machine: Machine) -> MachineTemplate? { all.first { $0.spec.task == machine.template } }
}

extension HelperModel {
    /// What a trial changes: the brief, the example policy and the model, together. Trust is earned per version.
    struct Version: Equatable {
        var brief: String
        var examples: Int?
        var runner: String?

        init(brief: String, examples: Int?, runner: String?) {
            self.brief = brief
            self.examples = examples
            self.runner = runner
        }

        init(_ spec: HelperSpec) { self.init(brief: spec.brief, examples: spec.examples, runner: spec.runner) }

        /// The version a decision moved to, and the one it came from.
        init(decision: Decision) {
            self.init(
                brief: decision.brief, examples: Int(decision.detail["examples", default: ""]),
                runner: decision.detail["runner"].flatMap(\.cleaned))
        }

        init(parentOf decision: Decision) {
            self.init(
                brief: decision.parentBrief, examples: Int(decision.detail["parentExamples", default: ""]),
                runner: decision.detail["parentRunner"].flatMap(\.cleaned))
        }

        func apply(to spec: HelperSpec) -> HelperSpec {
            var spec = spec
            spec.brief = brief
            spec.examples = examples
            spec.runner = runner
            return spec
        }

        /// How a decision records this version and its parent.
        func detail(parent: Version) -> [String: String] {
            [
                "examples": examples.map(String.init) ?? "", "parentExamples": parent.examples.map(String.init) ?? "",
                "runner": runner ?? "", "parentRunner": parent.runner ?? "",
            ]
        }
    }
}
