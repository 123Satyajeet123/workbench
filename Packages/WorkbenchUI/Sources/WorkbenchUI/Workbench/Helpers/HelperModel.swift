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

    let spec: HelperSpec
    /// The name shown for the helper, for its notification.
    let name: String
    let source: Source
    private(set) var day: WorkDay
    private(set) var items: [Item] = []
    /// The screen sessions of the shown day; empty for other sources.
    private(set) var sessions: [ScreenSession] = []
    private(set) var phase = ReadPhase.idle
    private(set) var problem: String?
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
        spec: HelperSpec, name: String, source: Source, store: Store,
        makeModel: ((ModelChoice) -> RecordedModel)? = nil, notifier: Notifier = SystemNotifier()
    ) {
        self.spec = spec
        self.name = name
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
        guard isReady, phase != .reading else { return false }
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

    /// Turning the nudge on asks macOS for permission to show it.
    func setNudge(on: Bool) async {
        if on, !(await notifier.prepare()) {
            problem = "macOS does not allow Workbench notifications. Allow them in System Settings › Notifications."
            return
        }
        nudge.isOn = on
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
        guard let message = spec.nudge?.message, isReady, nudge.isOn else { return }
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

/// The helpers of this Mac, built from their specs. The sidebar and Mochi's page read them from here.
@Observable
final class Crew {
    let team: HelperModel
    let timeline: HelperModel

    init(team: HelperModel, timeline: HelperModel) {
        self.team = team
        self.timeline = timeline
    }

    convenience init(store: Store, capture: CaptureService, founder: @escaping () -> String) throws {
        self.init(
            team: HelperModel(
                spec: .team, name: SidebarSelection.team.title,
                source: .whatsapp(
                    try WhatsAppSource(store: store, capture: capture, task: HelperSpec.team.task, founder: founder)),
                store: store),
            timeline: HelperModel(
                spec: .timeline, name: "Timeline", source: .screen(ScreenSource(store: store)), store: store))
    }

    func startNudges() {
        for helper in [team, timeline] { helper.startNudges() }
    }

    /// The helper behind a sidebar page; Mochi's page holds the timeline.
    func helper(for page: SidebarSelection) -> HelperModel? {
        switch page {
        case .team: team
        case .day: timeline
        case .calls, .runs: nil
        }
    }
}
