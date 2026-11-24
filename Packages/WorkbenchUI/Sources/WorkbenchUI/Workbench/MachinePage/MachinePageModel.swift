import Foundation
import Kernel
import Observation
import SwiftUI
import WorkbenchCore

/// The page of one machine as the person works on it: the page in its editor, the proposal that waits, and the
/// machine's facts. The store is the truth; every action writes to it and shows the page again.
@Observable
final class MachinePageModel {
    private(set) var proposal: PendingProposal?
    private(set) var facts: [Item] = []
    /// What the gate refused in the last request, in the words the person reads. The store keeps no refusal, so these
    /// last until the person decides on the proposal.
    private(set) var refusals: [PageRefusal] = []
    private(set) var isAsking = false
    /// The page in its editor; nil until the page is shown for the first time.
    private(set) var editor: PageEditorController?
    /// The fact whose proof the person opened, and the kind of source they are choosing for.
    var inspected: Item?
    var choosing: PickerKind?
    /// Whether the sheet with everything else about the machine is open.
    var isShowingMore = false
    /// What the words of the title and of the job do. The app that shows the page sets them.
    @ObservationIgnored var edits = PageEdits()

    let problems = ProblemSlot()
    let toast = ToastCenter()

    @ObservationIgnored let store: Store
    @ObservationIgnored let page: WorkObjectID
    /// Who writes the page; nil when this Mac cannot say, and the page is then read and never written.
    @ObservationIgnored let owner: PersonID?
    @ObservationIgnored let ownerNotice: String?
    @ObservationIgnored private let viewer: PageViewer
    @ObservationIgnored private let makeModel: () throws -> RecordedModel
    @ObservationIgnored unowned let helper: HelperModel
    /// What the machine says of itself at a moment: what it is doing, why it does not read, and its last reading.
    @ObservationIgnored let status: (Date) -> Result<MachineStatus, any Error>?

    init(
        helper: HelperModel, page: WorkObjectID, store: Store, owner: Result<PersonID, any Error>,
        status: @escaping (Date) -> Result<MachineStatus, any Error>? = { _ in nil },
        makeModel: @escaping () throws -> RecordedModel
    ) throws {
        guard NoteID(object: page) != nil else { throw WorkObjectError.unknown(page) }
        self.helper = helper
        self.page = page
        self.store = store
        self.makeModel = makeModel
        self.status = status
        switch owner {
        case .success(let person):
            self.owner = person
            ownerNotice = nil
            viewer = try PageViewer(owner: person)
            problems.attempt("start the page") { try store.startPage(of: helper.machine) }
        case .failure(let cause):
            self.owner = nil
            ownerNotice = Self.readOnlyNotice(cause: cause)
            viewer = .nobody
        }
        reload()
    }

    var name: String { helper.name }
    var spec: HelperSpec { helper.spec }
    var reads: String { helper.reads }
    /// The job in one sentence, in the person's words: the machine's own, else its template's.
    var job: String? { helper.machine.job }

    private static func readOnlyNotice(cause: any Error) -> String {
        "This page is read-only. \(cause.localizedDescription) To change it, allow Workbench in Keychain Access, then open this page again."
    }

    func reload() {
        problems.attempt("read the page") {
            proposal = try store.queries.pendingProposal(of: page, for: viewer)
            facts = helper.shown(
                try store.queries.parent(of: page).map { try store.queries.facts(in: $0, includeChildren: true) } ?? [])
        }
    }

    /// Reads the store again and shows the page again: the person may have changed it in another place.
    func refresh() {
        reload()
        problems.attempt("show the page") { try editor?.refresh() }
    }

    /// Opens the page in its editor, once. The look is the app's, as the editor takes it.
    func openEditor(appearance: EditorEnvironment.Appearance, reduceMotion: Bool, scale: Double) {
        guard editor == nil else { return }
        problems.attempt("open the page") {
            let controller = try PageEditorController(
                store: store, page: page, owner: owner, host: EditorHost(), appearance: appearance,
                reduceMotion: reduceMotion, scale: scale, views: { [unowned self] in viewBuilder },
                document: { [unowned self] in documentBlocks })
            controller.onMark = { [unowned self] fact, mark in markFact(fact, mark) }
            controller.onField = { [unowned self] field, text in edit(field: field, to: text) }
            controller.onOpen = { [unowned self] target in open(target) }
            controller.start()
            editor = controller
        }
    }

    /// What the machine's blocks show: its facts with the marks it offers for each, and what each picker can do.
    private var viewBuilder: MachineViewBuilder {
        MachineViewBuilder(
            facts: facts, titleOf: { [spec] item in item[spec.title] }, lens: FactsLens(spec: spec, now: Date()),
            pickerNote: { [helper] kind in PickerChoice.unavailableNote(kind, for: helper) },
            marks: { [unowned self] item in
                owner == nil ? [] : actions(for: item).compactMap(FactMark.init(action:))
            })
    }

    private func markFact(_ fact: Int64, _ mark: FactMark) {
        guard let item = facts.first(where: { $0.id == fact }) else { return }
        act(mark.action, on: item)
    }

    private func open(_ target: OpenTarget) {
        switch target {
        case .cite(let reference):
            if case .fact(let id) = PageCite(reference: reference) { inspected = facts.first { $0.id == id } }
        case .link(let address): EditorHost.openLink(address)
        case .picker(let source): choosing = PickerKind(rawValue: source)
        case .action(.read): Task { await helper.read() }
        case .action(.more): isShowingMore = true
        }
    }

    /// Sends a request to the machine. Nothing changes on the page until the person accepts what comes back. Answers
    /// whether a proposal was made, so the request stays in the box when it was not.
    func ask(_ request: String) async -> Bool {
        guard !isAsking, owner != nil, let words = request.cleaned else { return false }
        isAsking = true
        defer { isAsking = false }
        var isProposed = false
        await problems.attempt("ask \(name) to change the page", clearing: true) {
            await editor?.flush()
            let current = try store.queries.page(of: page, for: viewer)
            let composer = PageComposer(model: try makeModel())
            let proposal = try await composer.compose(
                words, page: current.page, notes: current.notes, spec: spec, items: facts,
                grounds: try store.queries.pageGrounds(of: page, items: facts),
                gate: PageGate(catalog: PageCatalog(spec: spec, items: facts)))
            try submit(proposal, asked: words)
            isProposed = true
        }
        return isProposed
    }

    /// Keeps what the machine proposed, with the refusals the person is told about.
    func submit(_ proposal: PageProposal, asked request: String) throws {
        guard let owner else { return }
        try store.propose(proposal, on: page, by: helper.machine.id, request: request, owner: owner)
        refusals = proposal.verdicts.compactMap(\.refusal)
        refresh()
    }

    func accept() async {
        guard let proposal else { return }
        await editor?.flush()
        decide("accept the change") { try store.accept(proposal: proposal.id, surface: .machinePage) }
    }

    func discard() {
        guard let proposal else { return }
        decide("throw the change away") { try store.discard(proposal: proposal.id, surface: .machinePage) }
    }

    private func decide(_ step: String, _ work: () throws -> Void) {
        problems.attempt(step, work)
        refusals = []
        refresh()
    }

    /// Marks or closes a fact the way every page does, and says so in a toast that can take it back.
    func act(_ action: FactAction, on item: Item) {
        let acting = PageFactActing(acting: MachineActing(helper: helper), changed: refresh)
        do {
            guard let undo = try acting.perform(action, on: [item], surface: .machinePage) else { return }
            toast.show(action.toastText(for: FactHeadline(item: item, title: item[spec.title]).words), undo: undo)
        } catch {
            toast.show(error.localizedDescription)
        }
    }

    func actions(for item: Item) -> [FactAction] { MachineActing(helper: helper).offered(for: item) }
}

/// Marks and closes a fact the way every page does, then asks the page to read its facts again.
final class PageFactActing: FactActing {
    private let acting: any FactActing
    private let changed: () -> Void

    init(acting: any FactActing, changed: @escaping () -> Void) {
        self.acting = acting
        self.changed = changed
    }

    func offered(for item: Item) -> [FactAction] { acting.offered(for: item) }

    func perform(_ action: FactAction, on items: [Item], surface: Surface) throws -> (() -> Void)? {
        let undo = try acting.perform(action, on: items, surface: surface)
        changed()
        return undo.map { undo in
            { [changed] in
                undo()
                changed()
            }
        }
    }
}

extension FactMark {
    init?(action: FactAction) {
        switch action {
        case .right: self = .right
        case .wrong: self = .wrong
        case .done: self = .done
        case .snooze, .notRelevant: return nil
        }
    }

    var action: FactAction {
        switch self {
        case .right: .right
        case .wrong: .wrong
        case .done: .done
        }
    }
}
