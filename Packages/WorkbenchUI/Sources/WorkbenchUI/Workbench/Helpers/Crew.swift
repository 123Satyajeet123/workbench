import CaptureService
import Foundation
import Observation
import WorkbenchCore

/// The machines of this Mac, one model each, built from the store's machine records. The founder adds, renames,
/// edits, pauses and deletes them here; Mochi's page holds the built-in timeline.
@Observable
final class Crew {
    private(set) var machines: [HelperModel] = []
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    @ObservationIgnored private var itemListeners: [() -> Void] = []
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let makeModel: ((ModelChoice) -> RecordedModel)?
    @ObservationIgnored private let alarm: VersionAlarm
    @ObservationIgnored private let openWebSession: () throws -> WebSession
    let notifications: Notifications

    convenience init(
        store: Store, capture: CaptureService, founder: @escaping () -> String,
        makeModel: ((ModelChoice) -> RecordedModel)? = nil, notifier: Notifier = SystemNotifier(),
        openWebSession: (() throws -> WebSession)? = nil
    ) {
        self.init(
            store: store, capture: capture, founder: founder, makeModel: makeModel,
            notifications: Notifications(notifier: notifier), openWebSession: openWebSession)
    }

    init(
        store: Store, capture: CaptureService, founder: @escaping () -> String,
        makeModel: ((ModelChoice) -> RecordedModel)?, notifications: Notifications,
        openWebSession: (() throws -> WebSession)? = nil
    ) {
        self.store = store
        self.openWebSession = openWebSession ?? { try WebResearchSettings(store: store).openSession() }
        self.capture = capture
        self.founder = founder
        self.makeModel = makeModel
        self.notifications = notifications
        alarm = VersionAlarm(store: store, notifications: notifications, problems: problems)
        reload()
    }

    /// Calls `listener` when any machine's items change. Each machine also re-checks its rollback alarm then.
    func onItemsChanged(_ listener: @escaping () -> Void) { itemListeners.append(listener) }

    /// Mochi's timeline: the built-in timeline machine, while it exists.
    var timeline: HelperModel? { machines.first { $0.spec.task == HelperSpec.timeline.task } }

    /// The machines in the sidebar's crew: every machine but Mochi's timeline.
    var crew: [HelperModel] { machines.filter { $0 !== timeline } }

    /// The machine a new machine that follows another would follow: the first with a lifecycle.
    var followable: HelperModel? { machines.first { $0.spec.lifecycle != nil } }

    static let nothingToFollow =
        "Add Pip first. This machine follows its open plans, blockers, commitments, questions and decisions."

    /// The criteria of the first Deal intake machine. A new Outbound machine starts with a copy of them, and then keeps
    /// its own: the editor shows whether the two still match.
    var intakeCriteria: Criteria? {
        machines.first { $0.machine.template == HelperSpec.dealIntake.task }?.spec.criteria
    }

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
        problems.attempt("log the switch") {
            try store.log(
                Decision(
                    at: store.clock(), task: helper.spec.task, kind: .promote, by: .person, brief: trial.version.brief,
                    parentBrief: parent.brief,
                    detail: HelperImprovement.counts(trial.result).merging(trial.version.detail(parent: parent)) {
                        a, _ in a
                    }
                )
            )
        }
        helper.endTrial()
    }

    func reload() {
        problems.attempt("read the machines") {
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
                    for listener in self?.itemListeners ?? [] { listener() }
                    if let model { self?.alarm.check(model, revert: { self?.revise($0, to: $1) }) }
                }
                model.schedule.start()
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
        var spec = spec
        if spec.needsFollowed {
            guard let followed = followable else {
                problems.show(Self.nothingToFollow)
                return nil
            }
            spec.follows = followed.spec.task
        }
        if template == HelperSpec.outbound.task, let intake = intakeCriteria { spec.criteria = intake }
        var id: Int64?
        problems.attempt("add the machine") {
            id = try store.createMachine(from: spec, template: template, name: name).id
        }
        reload()
        return id
    }

    /// The built-in this machine came from, when its design has moved on, and what the update changes.
    func update(for helper: HelperModel) -> (template: MachineTemplate, changes: [String])? {
        guard let template = MachineTemplate.all.first(where: { $0.spec.task == helper.machine.template }),
            let changes = helper.spec.update(toward: template.spec)
        else { return nil }
        return (template, changes)
    }

    /// The founder's choice to take the newer built-in design.
    func upgrade(_ helper: HelperModel) {
        guard let template = update(for: helper)?.template else { return }
        problems.attempt("update \(helper.name)") { try store.upgrade(helper.machine, to: template.spec) }
        reload()
    }

    func rename(_ helper: HelperModel, to name: String) {
        problems.attempt("rename \(helper.name)") { try store.rename(helper.machine, to: name) }
        reload()
    }

    func revise(_ helper: HelperModel, to version: HelperModel.Version) {
        problems.attempt("change \(helper.name)") {
            try store.revise(
                helper.machine, brief: version.brief, examples: version.examples, runner: version.runner)
        }
        reload()
    }

    func edit(_ helper: HelperModel, brief: String) {
        problems.attempt("change \(helper.name)'s brief") { try store.edit(helper.machine, brief: brief) }
        reload()
    }

    /// New criteria are a new prompt version, as a new brief is.
    func setCriteria(_ helper: HelperModel, _ criteria: Criteria) {
        problems.attempt("save \(helper.name)'s criteria") { try store.setCriteria(helper.machine, criteria) }
        reload()
    }

    func show(_ helper: HelperModel, as view: String) {
        problems.attempt("change \(helper.name)'s view") { try store.show(helper.machine, as: view) }
        reload()
    }

    func setPaused(_ helper: HelperModel, _ paused: Bool) {
        problems.attempt("pause \(helper.name)") { try store.setState(helper.machine, paused ? .paused : .active) }
        reload()
    }

    /// Deletes the machine, its items and marks, and its saved settings. Its runs stay in the meter.
    func delete(_ helper: HelperModel) {
        problems.attempt("delete \(helper.name)") { try store.setState(helper.machine, .deleted) }
        reload()
    }

    func dismissProblem() { problems.dismiss() }

    private func source(for machine: Machine) throws -> any MachineSource {
        switch machine.spec.source {
        case .screenSessions: ScreenSource(store: store)
        case .pageText: try PageSource(store: store, task: machine.task)
        case .mail: MailSource(store: store, capture: capture)
        case .news: NewsSource(store: store, capture: capture)
        case .webSearch:
            OutboundSource(store: store, capture: capture, task: machine.task, openSession: openWebSession)
        case .whatsappChat:
            try WhatsAppSource(store: store, capture: capture, task: machine.task, founder: founder)
        }
    }
}
