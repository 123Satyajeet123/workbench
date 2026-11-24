import CaptureService
import Foundation
import Kernel
import Observation
import WorkbenchCore

@Observable
final class HelperModel {
    let reading: HelperReading
    let improvement: HelperImprovement
    let schedule: HelperSchedule
    let agreement: HelperAgreement

    /// The machine's page as a document. Nil only when the page cannot open at all; `pageProblem` says why.
    private(set) var pageModel: MachinePageModel?
    private(set) var pageProblem: String?
    private(set) var items: [Item] = []
    private(set) var open: [Item] = []
    private(set) var closed: [Item] = []
    /// How close the helper's latest prompt and model are to earning trust, from audit answers on held-out days.
    private(set) var trust: Certificate.Status?

    @ObservationIgnored private let shared: MachineContext
    @ObservationIgnored private let owner: Result<PersonID, any Error>

    convenience init(
        machine: Machine, source: any MachineSource, store: Store, makeModel: ((ModelChoice) -> RecordedModel)? = nil,
        notifier: Notifier = SystemNotifier(), owner: Result<PersonID, any Error> = PageHost.noOwner
    ) {
        self.init(
            machine: machine, source: source, store: store, makeModel: makeModel,
            notifications: Notifications(notifier: notifier), owner: owner)
    }

    init(
        machine: Machine, source: any MachineSource, store: Store, makeModel: ((ModelChoice) -> RecordedModel)?,
        notifications: Notifications, owner: Result<PersonID, any Error> = PageHost.noOwner
    ) {
        let shared = MachineContext(
            machine: machine, source: source, store: store, makeModel: makeModel, notifications: notifications)
        let reading = HelperReading(context: shared)
        self.shared = shared
        self.owner = owner
        self.reading = reading
        improvement = HelperImprovement(context: shared)
        schedule = HelperSchedule(context: shared, reading: reading)
        agreement = HelperAgreement(context: shared)
        shared.reload = { [weak self] in self?.reload() }
        reload()
        openPage()
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
    var isChoosingSource: Bool { !isReady || source.isChanging }
    var context: [String: [String]] { source.context }
    var notifications: Notifications { shared.notifications }

    /// Called after a read or a mark changed this machine's items, so the review queue can follow.
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
    var weekly: WeeklySearch {
        get { schedule.weekly }
        set { schedule.weekly = newValue }
    }
    /// This machine searches the web for startups.
    var isOutbound: Bool { spec.source.findsStartups }
    var watch: WatchSchedule {
        get { schedule.watch }
        set { schedule.watch = newValue }
    }

    var mood: Mascot.Mood {
        if phase == .reading { return .working }
        if problem != nil { return .trouble }
        return question != nil ? .asking : .calm
    }

    /// The item the app picked to ask about, while it is unanswered. Its answer is evidence of the helper's error rate.
    var question: Item? { items.first { $0.askedWith != nil && $0.state == .proposed } }

    func items(on day: WorkDay) -> [Item] { shared.items(on: day) }

    func shown(_ items: [Item]) -> [Item] { shared.shown(items) }

    /// The machine's items of the last `days` days, as read: no call is set from the criteria.
    func items(since days: Int) -> [Item] {
        var found: [Item] = []
        attempt("read the deals") {
            found = shown(try shared.store.queries.items(of: spec.task, since: today.adding(days: -days)))
        }
        return found
    }

    func missing(on day: WorkDay) -> [String] { shared.missing(on: day) }

    /// The record after a rename, an edit or a pause. The source stays, so a chosen chat stays chosen.
    func update(_ machine: Machine) {
        shared.use(machine)
        if pageModel == nil { openPage() }
        reload()
    }

    /// The page is opened once, so the person's unsaved words stay while the machine's page is closed and open again.
    private func openPage() {
        do {
            guard let page = machine.page else { throw PageUnavailable() }
            pageModel = try MachinePageModel(
                helper: self, page: page, store: shared.store, owner: owner,
                status: { [weak self] now in self?.status(at: now) },
                makeModel: { [shared] in try shared.makeModel.current() })
            pageProblem = nil
        } catch {
            pageProblem = "The page of \(name) could not open: \(error.localizedDescription)"
        }
    }

    func show(_ day: WorkDay) {
        shared.show(day)
        reading.forgetResult()
        reload()
    }

    func reload() {
        attempt("read the day") {
            items = shown(try shared.store.queries.items(of: spec.task, day: day, scope: scope)).map(spec.scored)
            if let lifecycle = spec.lifecycle {
                open = shown(try shared.store.queries.openItems(of: spec.task, lifecycle: lifecycle).items)
                closed = shown(try shared.store.queries.closedItems(of: spec.task, from: day.start, to: day.end))
            }
            trust = try shared.store.queries.quality().first { $0.task == spec.task }?.heldOutAudit.status
            try source.refresh(on: day)
            try improvement.reload()
        }
    }

    func read() async { await reading.read(day) }

    /// What the machine says of itself at `now`, from the store alone. A view that calls this draws again when a
    /// reading starts or ends, when the machine is paused or resumed, and when its schedule changes; the store's own
    /// clock (the pause ends, the next reading falls due) is the caller's to tick.
    func status(at now: Date) -> Result<MachineStatus, any Error> {
        _ = (phase, watch, items.count)
        return Result {
            try shared.store.queries.status(
                of: machine, model: try? shared.makeModel.current().model, source: source.standing, now: now,
                zone: .current)
        }
    }

    func hasMissingSummaries(on day: WorkDay) -> Bool { reading.hasMissingSummaries(on: day) }
    func summarize(_ day: WorkDay) async -> Bool { await reading.summarize(day) }

    func close(_ item: Item, as outcome: String) {
        guard let id = item.id else { return }
        attempt("close the item") { try shared.store.close(item: id, as: outcome, surface: .machinePage) }
        itemsWereChanged()
    }

    /// The founder agrees with the close a line proposed. A model only proposes: nothing closes until this.
    func confirmClose(_ item: Item) {
        guard let id = item.id else { return }
        attempt("confirm the close") { try shared.store.confirmClose(item: id, surface: .machinePage) }
        itemsWereChanged()
    }

    func reopen(_ item: Item) {
        guard let id = item.id else { return }
        attempt("reopen the item") { try shared.store.reopen(item: id, surface: .machinePage) }
        itemsWereChanged()
    }

    /// Marking an item the same way again takes the mark back.
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

private struct PageUnavailable: LocalizedError {
    var errorDescription: String? { "this machine has no page yet." }
}

extension HelperModel {
    func startTrial(brief: String, by: Decision.By = .person, why: String = "") async {
        await improvement.startTrial(brief: brief, by: by, why: why)
    }

    func startTrial(_ version: Version, by: Decision.By, why: String) async {
        await improvement.startTrial(version, by: by, why: why)
    }

    func learnFromMarks() async { await improvement.learnFromMarks() }
    func improve() async { await improvement.improve() }
    func keepCurrent() { improvement.keepCurrent() }
    func endTrial() { improvement.endTrial() }

    func setNudge(on: Bool) async { await schedule.setNudge(on: on) }
    func setWatch(on: Bool) async { await schedule.setWatch(on: on) }
    func readIfDue() async { await schedule.readIfDue() }
    func nudgeIfDue() async { await schedule.nudgeIfDue() }
}
