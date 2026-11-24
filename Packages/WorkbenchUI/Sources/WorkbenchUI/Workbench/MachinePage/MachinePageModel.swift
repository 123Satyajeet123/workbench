import Foundation
import Kernel
import Observation
import SwiftUI
import WorkbenchCore

/// A text of the page that is edited in place.
enum PageField { case name, job }

/// The page of one machine as the person works on it: the live blocks, the proposal that waits, the machine's facts,
/// and the note the person writes in. The store is the truth; every action writes to it and reads the page again.
@Observable
final class MachinePageModel {
    private(set) var shown: ShownPage
    private(set) var proposal: PendingProposal?
    private(set) var facts: [Item] = []
    private(set) var runs: PageRuns
    /// What the gate refused in the last request, in the words the person reads. The store keeps no refusal, so these
    /// last until the person decides on the proposal.
    private(set) var refusals: [PageRefusal] = []
    private(set) var isAsking = false
    /// The words of the page the person is editing where they stand.
    private(set) var editing: PageField?

    let editor: NoteEditorModel
    let problems = ProblemSlot()
    let toast = ToastCenter()

    @ObservationIgnored let store: Store
    @ObservationIgnored private let page: WorkObjectID
    @ObservationIgnored private let owner: PersonID
    @ObservationIgnored private let viewer: PageViewer
    @ObservationIgnored private let makeModel: () throws -> RecordedModel
    @ObservationIgnored unowned let helper: HelperModel
    /// What the machine is doing now, in one line under the job. Nothing shows until a status read is given here.
    @ObservationIgnored let nowLine: () -> String?

    init(
        helper: HelperModel, page: WorkObjectID, store: Store, owner: PersonID,
        nowLine: @escaping () -> String? = { nil }, makeModel: @escaping () throws -> RecordedModel
    ) throws {
        guard let note = NoteID(object: page) else { throw WorkObjectError.unknown(page) }
        self.helper = helper
        self.page = page
        self.store = store
        self.owner = owner
        self.makeModel = makeModel
        self.nowLine = nowLine
        viewer = try PageViewer(owner: owner)
        editor = NoteEditorModel(note: note, store: store, owner: owner)
        shown = ShownPage(contents: PageContents(page: MachinePage(), notes: [], erased: []), proposal: nil)
        runs = PageRuns(order: [], documentBlocks: [])
        editor.pageOrder = { [weak self] saving in self?.pageOrder(saving: saving) ?? saving.map(PageBlockRef.note) }
        problems.attempt("start the page") { try store.startPage(of: helper.machine) }
        reload()
    }

    var name: String { helper.name }
    var spec: HelperSpec { helper.spec }
    var reads: String { helper.reads }
    /// The job in one sentence, in the person's words: the machine's own, else its template's.
    var job: String? { helper.machine.job }
    var slots: [PageSlot] { runs.slots(order: shown.order) }

    /// The title of the page as a text that is edited in place; `commit` gets the new name.
    func renaming(commit: @escaping (String) -> Void) -> PageRename {
        PageRename(
            isEditing: Binding(get: { self.editing == .name }, set: { self.setEditing(.name, $0) }), commit: commit)
    }

    func setEditing(_ field: PageField, _ isEditing: Bool) {
        if isEditing {
            editing = field
        } else if editing == field {
            editing = nil
        }
    }

    func reload() {
        problems.attempt("read the page") {
            let contents = try store.queries.page(of: page, for: viewer)
            proposal = try store.queries.pendingProposal(of: page, for: viewer)
            shown = ShownPage(contents: contents, proposal: proposal)
            facts = helper.shown(
                try store.queries.parent(of: page).map { try store.queries.facts(in: $0, includeChildren: true) } ?? [])
            placeParagraphs()
        }
    }

    /// Draws the note again from the store, then the page: the person may have changed either in another place.
    func refresh() {
        editor.reconcile()
        reload()
    }

    /// Sends a request to the machine. Nothing changes on the page until the person accepts what comes back. Answers
    /// whether a proposal was made, so the request stays in the box when it was not.
    func ask(_ request: String) async -> Bool {
        guard !isAsking, let words = request.cleaned else { return false }
        isAsking = true
        defer { isAsking = false }
        var isProposed = false
        await problems.attempt("ask \(name) to change the page", clearing: true) {
            await editor.flush()
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
        try store.propose(proposal, on: page, by: helper.machine.id, request: request, owner: owner)
        refusals = proposal.verdicts.compactMap(\.refusal)
        reload()
    }

    func accept() async {
        guard let proposal else { return }
        await editor.flush()
        decide("accept the change") { try store.accept(proposal: proposal.id, surface: .machinePage) }
    }

    func discard() {
        guard let proposal else { return }
        decide("throw the change away") { try store.discard(proposal: proposal.id, surface: .machinePage) }
    }

    func remove(_ block: MachineBlockID) {
        problems.attempt("remove the block") { try store.removeBlock(block, surface: .machinePage) }
        reload()
    }

    private func decide(_ step: String, _ work: () throws -> Void) {
        problems.attempt(step, work)
        refusals = []
        reload()
    }

    /// Marks or closes a fact the way every page does, and says so in a toast that can take it back.
    func act(_ action: FactAction, on item: Item) {
        let acting = PageFactActing(acting: MachineActing(helper: helper), changed: reload)
        do {
            guard let undo = try acting.perform(action, on: [item], surface: .machinePage) else { return }
            toast.show(action.toastText(for: FactHeadline(item: item, title: item[spec.title]).words), undo: undo)
        } catch {
            toast.show(error.localizedDescription)
        }
    }

    func actions(for item: Item) -> [FactAction] { MachineActing(helper: helper).offered(for: item) }
}

extension MachinePageModel {
    /// The run of paragraphs at `index` as a text view edits it.
    func run(_ index: Int) -> PageRun { PageRun(page: self, index: index) }

    fileprivate func pageOrder(saving: [BlockID]) -> [PageBlockRef] {
        runs.pageOrder(
            order: shown.order, documentBlocks: editor.document.blocks.map(\.id), saving: saving,
            liveBlock: shown.liveBlock(at:))
    }

    fileprivate func placeParagraphs() {
        runs = PageRuns(order: shown.order, documentBlocks: editor.document.blocks.map(\.id))
        if runs.sizes[runs.lastRun] == 0 { addParagraphAtEnd() }
    }

    /// A last run with no paragraph has nowhere to write. A new empty paragraph is not saved until it has words.
    private func addParagraphAtEnd() {
        let end = editor.text.utf16.count
        editor.edit(end..<end, with: "\n")
        runs.resize(runs.lastRun, by: 1)
    }

    fileprivate func text(ofRun index: Int) -> String { editor.document.text(of: runs.blocks(of: index)).text }

    fileprivate func edit(run index: Int, _ range: Range<Int>, with replacement: String) {
        let start = editor.document.text(of: runs.blocks(of: index)).start
        let before = editor.document.blocks.count
        editor.edit((start + range.lowerBound)..<(start + range.upperBound), with: replacement)
        runs.resize(index, by: editor.document.blocks.count - before)
    }

    /// A paragraph moves inside its run only: it never crosses a machine block.
    fileprivate func moveBlock(inRun index: Int, atOffset offset: Int, by distance: Int) -> Int {
        let range = runs.blocks(of: index)
        let start = editor.document.text(of: range).start
        let current = editor.document.blocks.firstIndex { $0.id == editor.document.blockID(at: start + offset) }
        let target = min(max((current ?? range.lowerBound) + distance, range.lowerBound), range.upperBound - 1)
        let moved = editor.moveBlock(atOffset: start + offset, by: target - (current ?? target))
        return moved - start
    }

    fileprivate var editorRevision: Int { editor.revision }
    fileprivate func setComposing(_ isComposing: Bool) { editor.isComposing = isComposing }
}

/// One run of paragraphs, edited as a text of its own over the page's one note.
struct PageRun: NoteRunEditing {
    let page: MachinePageModel
    let index: Int

    var text: String { page.text(ofRun: index) }
    var revision: Int { page.editorRevision }
    func edit(_ range: Range<Int>, with replacement: String) { page.edit(run: index, range, with: replacement) }
    func moveBlock(atOffset offset: Int, by distance: Int) -> Int {
        page.moveBlock(inRun: index, atOffset: offset, by: distance)
    }
    func setComposing(_ isComposing: Bool) { page.setComposing(isComposing) }
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
