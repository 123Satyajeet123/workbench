import CaptureService
import Foundation
import Kernel
import LocalSources
import Observation
import TelegramReader
import WorkbenchCore

@Observable
final class Crew {
    private(set) var machines: [HelperModel] = []
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    @ObservationIgnored private var itemListeners: [() -> Void] = []
    @ObservationIgnored let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let makeModel: ((ModelChoice) -> RecordedModel)?
    @ObservationIgnored let owner: Result<PersonID, any Error>
    @ObservationIgnored let whatsAppContainer: URL
    @ObservationIgnored private let alarm: VersionAlarm
    @ObservationIgnored private let openWebSession: () throws -> WebSession
    let notifications: Notifications
    let telegram: TelegramAccount

    convenience init(
        store: Store, capture: CaptureService, founder: @escaping () -> String,
        makeModel: ((ModelChoice) -> RecordedModel)? = nil, notifier: Notifier = SystemNotifier(),
        owner: Result<PersonID, any Error> = PageHost.noOwner, openWebSession: (() throws -> WebSession)? = nil,
        whatsAppContainer: URL = WhatsAppChatReader.defaultContainer, telegram: TelegramAccount? = nil
    ) {
        self.init(
            store: store, capture: capture, founder: founder, makeModel: makeModel,
            notifications: Notifications(notifier: notifier), owner: owner, openWebSession: openWebSession,
            whatsAppContainer: whatsAppContainer, telegram: telegram)
    }

    init(
        store: Store, capture: CaptureService, founder: @escaping () -> String,
        makeModel: ((ModelChoice) -> RecordedModel)?, notifications: Notifications,
        owner: Result<PersonID, any Error> = PageHost.noOwner, openWebSession: (() throws -> WebSession)? = nil,
        whatsAppContainer: URL = WhatsAppChatReader.defaultContainer, telegram: TelegramAccount? = nil
    ) {
        self.whatsAppContainer = whatsAppContainer
        self.store = store
        self.openWebSession =
            openWebSession ?? { try WebResearchSettings(store: store, secrets: Profile.yours.secrets).openSession() }
        self.capture = capture
        self.founder = founder
        self.makeModel = makeModel
        self.owner = owner
        self.notifications = notifications
        self.telegram =
            telegram
            ?? TelegramAccount(
                service: TDLibTelegram(folder: store.directory.appending(path: "Telegram")),
                capture: capture, store: store, secrets: Profile.yours.secrets)
        alarm = VersionAlarm(store: store, notifications: notifications, problems: problems)
        reload()
    }

    /// Calls `listener` when any machine's items change. Each machine also re-checks its rollback alarm then.
    func onItemsChanged(_ listener: @escaping () -> Void) { itemListeners.append(listener) }

    /// The machines that read what the person did on the screen. The Timeline page shows all of them.
    var screenReaders: [HelperModel] { machines.filter { $0.spec.readsScreen } }

    /// The machines whose facts open and close.
    var factKeepers: [HelperModel] { machines.filter { $0.spec.keepsFacts } }

    /// The machines that read open facts and write findings about them.
    var factReaders: [HelperModel] { machines.filter(\.spec.needsFollowed) }

    /// The machines that have a page of their own: the ones the Timeline page does not show.
    var crew: [HelperModel] { machines.filter { !$0.spec.readsScreen } }

    static let nothingToFollow = GalleryStartError.nothingToFollowWords

    /// The machine that rates nearest to the folder of `helper`, other than `helper`. A new machine that rates starts
    /// with a copy of its criteria, and then keeps its own: the editor shows whether the two still match.
    func thesisSource(for helper: HelperModel) -> HelperModel? {
        thesisSource(in: helper.machine.folder, besides: helper)
    }

    private func thesisSource(in folder: WorkObjectID?, besides helper: HelperModel? = nil) -> HelperModel? {
        folderTree().nearest(
            in: machines.filter { $0 !== helper && $0.spec.rates }, to: folder, folderOf: \.machine.folder)
    }

    private func folderTree() -> FolderTree {
        var tree = FolderTree()
        problems.attempt("read the folders") { tree = try store.queries.folderTree() }
        return tree
    }

    /// The names of the other machines that read this chat.
    func otherReaders(of chat: WhatsAppChat, besides helper: HelperModel) -> [String] {
        machines.filter { $0 !== helper && $0.source.chosenContainers.contains { $0.id == chat.jid } }.map(\.name)
    }

    /// Stops reading a chat for every machine that reads it, and erases what was stored from it.
    func stopReading(_ chat: WhatsAppChat) throws {
        try WhatsAppSource.stopReading(chat, among: machines.map(\.source), capture: capture)
    }

    func helper(id: Int64) -> HelperModel? { machines.first { $0.machine.id == id } }

    /// The spec of the facts of a task: a machine's own, or that of facts no machine keeps.
    func spec(ofTask task: String) -> HelperSpec? {
        helper(task: task)?.spec ?? HelperSpec.withoutMachine.first { $0.spec.task == task }?.spec
    }

    func helper(task: String) -> HelperModel? { machines.first { $0.spec.task == Trial.machineTask(of: task) } }

    /// The name of the machine that keeps a task's items.
    func name(ofTask task: String) -> String {
        if let keeper = HelperSpec.withoutMachine.first(where: { $0.spec.task == task }) { return keeper.name }
        guard let name = helper(task: task)?.name else {
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
                    notifications: notifications, owner: owner)
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
    func create(from template: MachineTemplate, name: String, in folder: WorkObjectID? = nil) -> Int64? {
        create(spec: template.spec, template: template.spec.task, name: name.cleaned ?? template.name, in: folder)
    }

    @discardableResult
    func create(spec: HelperSpec, template: String?, name: String, in folder: WorkObjectID? = nil) -> Int64? {
        var spec = spec
        var landing: WorkObjectID?
        problems.attempt("find the folder") {
            landing = try store.queries.folder(forNewMachineOf: template, in: folder)
        }
        var followed: HelperSpec?
        problems.attempt("find the machine to follow") { followed = try store.following(spec, landing: landing) }
        guard let followed else {
            problems.show(Self.nothingToFollow)
            return nil
        }
        spec = followed
        if spec.rates, let source = thesisSource(in: landing) { spec.criteria = source.spec.criteria }
        var id: Int64?
        problems.attempt("add the machine") {
            id =
                try template.map { try store.createMachine(from: spec, template: $0, name: name, in: folder) }?.id
                ?? store.createMachine(withoutTemplate: spec, name: name, in: folder).id
        }
        reload()
        return id
    }

    /// A machine over `source` for the job in `job`, with no template. It lands in `folder`, or among the roots.
    @discardableResult
    func createBlank(over source: SourceDescriptor, job: String, name: String, in folder: WorkObjectID? = nil) -> Int64?
    {
        guard let spec = HelperSpec(blankOver: source, job: job) else {
            problems.show(HelperSpecError.noJob.localizedDescription)
            return nil
        }
        return create(spec: spec, template: nil, name: name, in: folder)
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

    func setJob(_ helper: HelperModel, to job: String) {
        problems.attempt("change \(helper.name)'s job") { try store.edit(helper.machine, job: job) }
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

    /// The containers that the other machines over the same kind of source read.
    private func containers(readBesides machine: Machine) -> Set<String> {
        let others = machines.filter {
            $0.spec.task != machine.task && $0.spec.source.consent == machine.spec.source.consent
        }
        return Set(others.flatMap(\.source.chosenContainers).map(\.id))
    }

    private func source(for machine: Machine) throws -> any MachineSource {
        guard let make = Self.sourceMakers[machine.spec.source.key] else { throw NotAMachineSource() }
        return try make(self, machine)
    }

    private static let sourceMakers: [String: (Crew, Machine) throws -> any MachineSource] = [
        SourceDescriptor.screenWindow.key: { crew, _ in ScreenSource(store: crew.store) },
        SourceDescriptor.webPage.key: { crew, machine in try PageSource(store: crew.store, task: machine.task) },
        SourceDescriptor.gmailMail.key: { crew, _ in MailSource(store: crew.store, capture: crew.capture) },
        SourceDescriptor.newsArticle.key: { crew, _ in NewsSource(store: crew.store, capture: crew.capture) },
        SourceDescriptor.webSearch.key: { crew, machine in
            OutboundSource(
                store: crew.store, capture: crew.capture, task: machine.task, openSession: crew.openWebSession)
        },
        SourceDescriptor.whatsAppChat.key: { crew, machine in
            try WhatsAppSource(
                store: crew.store, capture: crew.capture, task: machine.task, founder: crew.founder,
                container: crew.whatsAppContainer)
        },
        SourceDescriptor.telegramChat.key: { crew, machine in
            try TelegramSource(
                store: crew.store, capture: crew.capture, account: crew.telegram, task: machine.task,
                founder: crew.founder, othersReading: { [weak crew] in crew?.containers(readBesides: machine) ?? [] })
        },
    ]

    /// The sources a person can choose for a machine made from a job alone: those the registry names that give days
    /// of lines and that a reader here can make a machine over.
    static var blankMachineSources: [SourceDescriptor] {
        SourceRegistry.all.filter { $0.givesDaysOfLines && sourceMakers[$0.key] != nil }
    }
}

/// A call's transcript is read once, after its notes, by `CallFollowUps`; no machine of the crew reads it.
struct NotAMachineSource: Error {}
