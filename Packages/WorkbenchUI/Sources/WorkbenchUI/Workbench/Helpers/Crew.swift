import CaptureService
import Foundation
import Observation
import TelegramReader
import WorkbenchCore

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
    let notifications: Notifications
    let telegram: TelegramAccount

    convenience init(
        store: Store, capture: CaptureService, founder: @escaping () -> String,
        makeModel: ((ModelChoice) -> RecordedModel)? = nil, notifier: Notifier = SystemNotifier(),
        telegram: TelegramAccount? = nil
    ) {
        self.init(
            store: store, capture: capture, founder: founder, makeModel: makeModel,
            notifications: Notifications(notifier: notifier), telegram: telegram)
    }

    init(
        store: Store, capture: CaptureService, founder: @escaping () -> String,
        makeModel: ((ModelChoice) -> RecordedModel)?, notifications: Notifications, telegram: TelegramAccount? = nil
    ) {
        self.store = store
        self.capture = capture
        self.founder = founder
        self.makeModel = makeModel
        self.notifications = notifications
        self.telegram =
            telegram
            ?? TelegramAccount(
                service: TDLibTelegram(folder: AppLaunch.defaultStoreFolder.appending(path: "Telegram")),
                capture: capture)
        alarm = VersionAlarm(store: store, notifications: notifications, problems: problems)
        reload()
    }

    func onItemsChanged(_ listener: @escaping () -> Void) { itemListeners.append(listener) }

    var timeline: HelperModel? { machines.first { $0.spec.task == HelperSpec.timeline.task } }

    var team: HelperModel? { machines.first { $0.machine.template == HelperSpec.team.task } }

    var sentinel: HelperModel? { machines.first { $0.machine.template == HelperSpec.derailment.task } }

    var crew: [HelperModel] { machines.filter { $0 !== timeline } }

    var followable: HelperModel? { machines.first { $0.spec.lifecycle != nil } }

    static let nothingToFollow =
        "Add Pip first. This machine follows its open plans, blockers, commitments, questions and decisions."

    func helper(id: Int64) -> HelperModel? { machines.first { $0.machine.id == id } }

    func helper(task: String) -> HelperModel? { machines.first { $0.spec.task == Trial.machineTask(of: task) } }

    func name(ofTask task: String) -> String {
        guard let name = helper(task: task)?.name else {
            return task
        }
        return Trial.isTrial(task) ? "\(name) · new brief" : name
    }

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
        var id: Int64?
        problems.attempt("add the machine") {
            id = try store.createMachine(from: spec, template: template, name: name).id
        }
        reload()
        return id
    }

    func update(for helper: HelperModel) -> (template: MachineTemplate, changes: [String])? {
        guard let template = MachineTemplate.of(helper.machine),
            let changes = helper.spec.update(toward: template.spec)
        else { return nil }
        return (template, changes)
    }

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

    func delete(_ helper: HelperModel) {
        problems.attempt("delete \(helper.name)") { try store.setState(helper.machine, .deleted) }
        reload()
    }

    private func whatsAppChats(except task: String) -> Set<String> {
        let others = machines.filter { $0.spec.task != task }.compactMap { $0.source as? WhatsAppSource }
        return Set(others.flatMap(\.chats).map(\.jid))
    }

    private func telegramChats(except task: String) -> Set<String> {
        let others = machines.filter { $0.spec.task != task }.compactMap { $0.source as? TelegramSource }
        return Set(others.compactMap(\.chat?.label))
    }

    private func source(for machine: Machine) throws -> any MachineSource {
        switch machine.spec.source {
        case .screenSessions: ScreenSource(store: store)
        case .pageText: try PageSource(store: store, task: machine.task)
        case .mail: MailSource(store: store, capture: capture)
        case .whatsappChat:
            try WhatsAppSource(
                store: store, capture: capture, task: machine.task, founder: founder,
                othersReading: { [weak self] in self?.whatsAppChats(except: machine.task) ?? [] })
        case .telegramChat:
            try TelegramSource(
                store: store, capture: capture, account: telegram, task: machine.task, founder: founder,
                othersReading: { [weak self] in self?.telegramChats(except: machine.task) ?? [] })
        }
    }
}
