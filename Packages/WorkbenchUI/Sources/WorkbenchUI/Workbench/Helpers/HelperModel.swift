import CaptureService
import Foundation
import Observation
import WorkbenchCore

@Observable
final class HelperModel {
    let reading: HelperReading
    let improvement: HelperImprovement
    let schedule: HelperSchedule
    let agreement: HelperAgreement

    private(set) var items: [Item] = []
    private(set) var open: [Item] = []
    private(set) var closed: [Item] = []
    private(set) var trust: Certificate.Status?

    @ObservationIgnored private let shared: MachineContext

    convenience init(
        machine: Machine, source: any MachineSource, store: Store, makeModel: ((ModelChoice) -> RecordedModel)? = nil,
        notifier: Notifier = SystemNotifier()
    ) {
        self.init(
            machine: machine, source: source, store: store, makeModel: makeModel,
            notifications: Notifications(notifier: notifier))
    }

    init(
        machine: Machine, source: any MachineSource, store: Store, makeModel: ((ModelChoice) -> RecordedModel)?,
        notifications: Notifications
    ) {
        let shared = MachineContext(
            machine: machine, source: source, store: store, makeModel: makeModel, notifications: notifications)
        let reading = HelperReading(context: shared)
        self.shared = shared
        self.reading = reading
        improvement = HelperImprovement(context: shared)
        schedule = HelperSchedule(context: shared, reading: reading)
        agreement = HelperAgreement(context: shared)
        shared.reload = { [weak self] in self?.reload() }
        reload()
    }

    var machine: Machine { shared.machine }
    var source: any MachineSource { shared.source }
    var spec: HelperSpec { shared.spec }
    var name: String { shared.name }
    var role: String { isPaused ? "Paused" : MachineTemplate.of(machine)?.role ?? "" }
    var isPaused: Bool { shared.isPaused }
    var day: WorkDay { shared.day }
    var today: WorkDay { shared.today }
    var scope: String { source.scope }
    var isReady: Bool { source.isReady }
    var isChoosingSource: Bool {
        !isReady || (source as? WhatsAppSource)?.isChanging == true || (source as? TelegramSource)?.isChanging == true
    }
    var context: [String: [String]] { source.context }
    var notifications: Notifications { shared.notifications }

    var itemsChanged: () -> Void {
        get { shared.itemsChanged }
        set { shared.itemsChanged = newValue }
    }

    var problem: String? { shared.problems.text }
    var problems: ProblemSlot { shared.problems }
    var phase: ReadPhase { reading.phase }
    var trial: TrialRun? { improvement.trial }
    var trialPhase: ReadPhase { improvement.trialPhase }
    var decisions: [Decision] { improvement.decisions }
    var improveNote: String? { improvement.improveNote }
    var notice: String? {
        get { improvement.notice }
        set { improvement.notice = newValue }
    }
    var nudge: NudgeSchedule {
        get { schedule.nudge }
        set { schedule.nudge = newValue }
    }
    var watch: WatchSchedule {
        get { schedule.watch }
        set { schedule.watch = newValue }
    }

    var mood: Mascot.Mood {
        if phase == .reading { return .working }
        if problem != nil { return .trouble }
        return question != nil ? .asking : .calm
    }

    var question: Item? { items.first { $0.askedWith != nil && $0.state == .proposed } }

    func items(on day: WorkDay) -> [Item] { shared.items(on: day) }

    func items(since days: Int) -> [Item] {
        var found: [Item] = []
        attempt("read the deals") {
            found = try shared.store.queries.items(of: spec.task, since: today.adding(days: -days))
        }
        return found
    }

    func missing(on day: WorkDay) -> [String] { shared.missing(on: day) }

    func update(_ machine: Machine) {
        shared.use(machine)
        reload()
    }

    func show(_ day: WorkDay) {
        shared.show(day)
        reading.forgetResult()
        reload()
    }

    func reload() {
        attempt("read the day") {
            items = try shared.store.queries.items(of: spec.task, day: day, scope: scope).map(spec.scored)
            if let lifecycle = spec.lifecycle {
                open = try shared.store.queries.openItems(of: spec.task, lifecycle: lifecycle)
                closed = try shared.store.queries.closedItems(of: spec.task, from: day.start, to: day.end)
            }
            trust = try shared.store.queries.quality().first { $0.task == spec.task }?.heldOutAudit.status
            try source.refresh(on: day)
            try improvement.reload()
        }
    }

    func read() async { await reading.read(day) }

    func hasMissingSummaries(on day: WorkDay) -> Bool { reading.hasMissingSummaries(on: day) }
    func summarize(_ day: WorkDay) async -> Bool { await reading.summarize(day) }

    func close(_ item: Item, as outcome: String) {
        guard let id = item.id else { return }
        attempt("close the item") { try shared.store.close(item: id, as: outcome) }
        itemsWereChanged()
    }

    func reopen(_ item: Item) {
        guard let id = item.id else { return }
        attempt("reopen the item") { try shared.store.reopen(item: id) }
        itemsWereChanged()
    }

    func mark(_ item: Item, as mark: Mark) {
        guard let id = item.id else { return }
        attempt("save the mark") { try shared.store.mark(item: id, as: item.state == mark ? .proposed : mark) }
        itemsWereChanged()
    }

    func attempt(_ step: String, _ work: () throws -> Void) { shared.problems.attempt(step, work) }

    private func itemsWereChanged() {
        reload()
        itemsChanged()
    }
}

extension HelperModel {
    func startTrial(brief: String, by: Decision.By = .person, why: String = "") async {
        await improvement.startTrial(brief: brief, by: by, why: why)
    }

    func startTrial(_ version: Version, by: Decision.By, why: String) async {
        await improvement.startTrial(version, by: by, why: why)
    }

    func tryModel(_ choice: ModelChoice) async { await improvement.tryModel(choice) }
    func learnFromMarks() async { await improvement.learnFromMarks() }
    func improve() async { await improvement.improve() }
    func keepCurrent() { improvement.keepCurrent() }
    func endTrial() { improvement.endTrial() }

    func setNudge(on: Bool) async { await schedule.setNudge(on: on) }
    func setWatch(on: Bool) async { await schedule.setWatch(on: on) }
    func readIfDue() async { await schedule.readIfDue() }
    func nudgeIfDue() async { await schedule.nudgeIfDue() }
}
