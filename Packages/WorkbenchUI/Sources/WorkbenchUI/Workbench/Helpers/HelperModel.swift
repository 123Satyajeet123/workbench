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
    private(set) var phase = ReadPhase.idle
    private(set) var problem: String?
    /// macOS blocks Workbench notifications; the nudge row offers System Settings.
    private(set) var notificationsBlocked = false
    var nudge = NudgeSchedule() {
        didSet { attempt("save the nudge") { try store.saveState(Self.json(nudge), forKey: nudgeKey) } }
    }

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
        case .screen: ""
        case .whatsapp(let chat): chat.chat?.jid ?? ""
        }
    }

    /// A chat helper reads nothing until the founder chose its chat.
    var isReady: Bool {
        switch source {
        case .screen: true
        case .whatsapp(let chat): chat.chat != nil
        }
    }

    /// The named sets the view and the nudge use, as far as they are known now.
    var context: [String: [String]] {
        switch source {
        case .screen: [:]
        case .whatsapp(let chat): ["members": chat.members]
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
        }
    }

    /// Sends the shown day to the chosen model and stores the items that pass the checks.
    func read() async { await read(day) }

    /// Marking an item the same way again takes the mark back.
    func mark(_ item: Item, as mark: Mark) {
        guard let id = item.id else { return }
        attempt("save the mark") { try store.mark(item: id, as: item.state == mark ? .proposed : mark) }
        reload()
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
            let result = try await reader.read(day: day, scope: scope, evidence: evidence)
            try store.saveReading(result, of: spec, day: day, scope: scope, grant: try await grant(scope))
            if self.day == day { reload() }
            phase = .read(kept: result.items.count, dropped: result.dropped)
            problem = nil
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
        }
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
        machines.first { $0.spec.task == task }?.name ?? task
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
                model.startNudges()
                return model
            }
        }
    }

    @discardableResult
    func create(from template: MachineTemplate, name: String) -> Int64? {
        var id: Int64?
        attempt("add the machine") {
            id = try store.createMachine(from: template.spec, name: name.cleaned ?? template.name).id
        }
        reload()
        return id
    }

    func rename(_ helper: HelperModel, to name: String) {
        attempt("rename \(helper.name)") { try store.rename(helper.machine, to: name) }
        reload()
    }

    func edit(_ helper: HelperModel, brief: String) {
        attempt("change \(helper.name)'s brief") { try store.edit(helper.machine, brief: brief) }
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
    static let all = [team, timeline]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func of(_ machine: Machine) -> MachineTemplate? { all.first { $0.spec.task == machine.template } }
}
