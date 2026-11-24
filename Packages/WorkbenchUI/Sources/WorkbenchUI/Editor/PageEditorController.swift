import Foundation
import Kernel
import WorkbenchCore

/// Joins the stored page of a machine to the editor. It shows the page to the editor, turns the person's ops into
/// store calls, and shows what the store changed in answer. Swift is the one writer: the editor holds only a view of
/// the committed page and the person's own typing.
///
/// A paragraph of the person is one line of the note, kept under the id the editor gives it; its machine blocks stay
/// where the person put them. A block the person deletes is erased with its lines. A proposal that waits shows in the
/// page as blocks that say how they stand; it is stored only when the person accepts it.
final class PageEditorController {
    private let store: Store
    private let note: NoteID
    private let page: WorkObjectID
    /// Who writes the page; nil when that is not known, and the page is then read and never written.
    private let owner: PersonID?
    private let viewer: PageViewer
    let host: EditorHost
    private let views: () throws -> MachineViewBuilder
    private let document: () -> DocumentBlocks
    private(set) var model: PageModel
    /// Each block that is not a paragraph of the person, as the editor holds it.
    private var shownBlocks: [String: PageBlockData] = [:]
    private var environment: EditorEnvironment
    private var processing: Task<Void, Never>?
    private var idles = 0

    /// How many times the page wrote the store: the checks watch it.
    private(set) var storeWrites = 0
    private(set) var blockedLoads: [EditorMessage] = []
    /// Why the last save failed, in words for the person. The words stay in the editor and are saved again.
    private(set) var problem: String?
    var onMark: (Int64, FactMark) -> Void = { _, _ in }
    var onField: (_ block: String, _ text: String) -> Void = { _, _ in }
    var onHeading: (_ block: String, _ text: String) -> Void = { _, _ in }
    var onSetting: (_ key: String, _ value: String) -> Void = { _, _ in }
    var onAsk: (_ request: String) -> Void = { _ in }
    var onOpen: (OpenTarget) -> Void = { _ in }

    init(
        store: Store, page: WorkObjectID, owner: PersonID?, host: EditorHost, appearance: EditorEnvironment.Appearance,
        reduceMotion: Bool, scale: Double = 1, views: @escaping () throws -> MachineViewBuilder,
        document: @escaping () -> DocumentBlocks = { .none }
    ) throws {
        guard let note = NoteID(object: page) else { throw WorkObjectError.unknown(page) }
        self.store = store
        self.note = note
        self.page = page
        self.owner = owner
        self.host = host
        self.views = views
        self.document = document
        let viewer = try owner.map { try PageViewer(owner: $0) } ?? .nobody
        self.viewer = viewer
        let (contents, shown) = try Self.read(store, page, viewer)
        model = PageModel(contents: contents, shown: shown, document: document())
        environment = Self.environment(appearance, reduceMotion, scale, editable: owner != nil)
        host.onMessage = { [weak self] message in self?.receive(message) }
    }

    func start() { host.load() }

    func setAppearance(_ appearance: EditorEnvironment.Appearance, reduceMotion: Bool, scale: Double) {
        environment = Self.environment(appearance, reduceMotion, scale, editable: owner != nil)
        host.send(.environment(environment))
    }

    private static func environment(
        _ appearance: EditorEnvironment.Appearance, _ reduceMotion: Bool, _ scale: Double, editable: Bool
    ) -> EditorEnvironment {
        EditorEnvironment(
            appearance: appearance, reduceMotion: reduceMotion, editable: editable,
            tokens: EditorTokens.resolved(for: appearance, scale: scale))
    }

    /// The page as stored, and as shown: the stored page with the pending proposal worked in.
    private static func read(_ store: Store, _ page: WorkObjectID, _ viewer: PageViewer) throws -> (
        PageContents, ShownPage
    ) {
        let contents = try store.queries.page(of: page, for: viewer)
        return (
            contents, ShownPage(contents: contents, proposal: try store.queries.pendingProposal(of: page, for: viewer))
        )
    }

    /// Asks the editor for the ops that wait, and waits until they are saved. False when the editor did not answer in
    /// time, because the person is composing a word.
    @discardableResult
    func flush(timeout: Duration = .seconds(5)) async -> Bool {
        let answered = idles + 1
        host.send(.flush)
        let deadline = ContinuousClock.now + timeout
        while idles < answered, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return idles >= answered
    }

    /// The same, for the app that quits: it waits for the answer here, at most `timeout`, while the main loop runs.
    func flushBeforeQuit(timeout: Duration = .seconds(2)) {
        let answered = idles + 1
        host.send(.flush)
        let deadline = ContinuousClock.now + timeout
        while idles < answered, ContinuousClock.now < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }

    /// Shows what the store holds now: blocks of machines that came, changed or left, and paragraphs that were erased
    /// elsewhere. What the person is typing stays.
    func refresh() throws {
        let (_, shown) = try Self.read(store, page, viewer)
        let builder = try views()
        let blocks = document()
        var changes: [PageChange] = []
        let held = Set(shown.order.map(\.rawValue)).union(blocks.ids)
        for id in model.order where !held.contains(id) {
            let before = model.order.count
            model.forget(id)
            if model.order.count < before {
                shownBlocks[id] = nil
                changes.append(.remove(id: id))
            }
        }
        var previous: String?
        func sync(_ block: PageBlockData) {
            let id = block.id
            if model.machines.contains(id) {
                if shownBlocks[id] != block { changes.append(.update(block: block)) }
            } else {
                changes.append(.insert(after: previous, block: block))
                model.show(machine: id, after: previous)
            }
            shownBlocks[id] = block
            previous = id
        }
        blocks.head.forEach(sync)
        for place in shown.order {
            if case .machine(let block) = place, let entry = shown.blocks[block] {
                model.stand(block.rawValue, for: shown.liveBlock(at: block))
                sync(
                    .machine(
                        id: block.rawValue,
                        view: builder.view(of: entry.block, id: block.rawValue, erased: entry.isErased),
                        standing: entry.standing))
            } else if model.order.contains(place.rawValue) {
                previous = place.rawValue
            }
        }
        blocks.tail.forEach(sync)
        if !changes.isEmpty { host.send(.apply(changes)) }
    }

    // MARK: From the editor

    private func receive(_ message: EditorMessage) {
        switch message {
        case .ready:
            host.send(.environment(environment))
            problem = capture { try load() }
        case .ops(let seq, let ops): enqueue { await self.save(seq, ops) }
        case .open(let target): onOpen(target)
        case .blocked: blockedLoads.append(message)
        case .idle: idles += 1
        case .layout(let height, let caret): host.fit(height: height, caret: caret)
        }
    }

    private func load() throws {
        let (contents, shown) = try Self.read(store, page, viewer)
        let builder = try views()
        let blocks = document()
        model = PageModel(contents: contents, shown: shown, document: blocks)
        shownBlocks = [:]
        let notes = Dictionary(uniqueKeysWithValues: contents.notes.map { ($0.id, $0.text) })
        let stored = shown.order.compactMap { place -> PageBlockData? in
            switch place {
            case .note(let block): return notes[block].map { .note(id: block.rawValue, text: $0) }
            case .machine(let block):
                guard let entry = shown.blocks[block] else { return nil }
                return .machine(
                    id: block.rawValue, view: builder.view(of: entry.block, id: block.rawValue, erased: entry.isErased),
                    standing: entry.standing)
            }
        }
        let all = blocks.head + stored + blocks.tail
        for block in all {
            if case .note = block { continue }
            shownBlocks[block.id] = block
        }
        host.send(.load(all))
    }

    private func enqueue(_ work: @escaping () async -> Void) {
        let before = processing
        processing = Task {
            await before?.value
            await work()
        }
    }

    private func save(_ seq: Int, _ ops: [EditorOp]) async {
        let blocks = document()
        let kept = ops.filter { op in
            guard case .delete(let id) = op else { return true }
            return !blocks.ids.contains(id)
        }
        model.apply(kept)
        let restored = ops.count - kept.count > 0 ? restore(blocks, after: ops) : []
        defer { if !restored.isEmpty { host.send(.apply(restored)) } }
        for case .mark(let fact, let mark) in ops { onMark(fact, mark) }
        for case .field(let id, let text) in ops { change(field: id, to: text) }
        for case .heading(let block, let text) in ops { onHeading(block, text) }
        for case .setting(let key, let value) in ops { onSetting(key, value) }
        for case .ask(let request) in ops { onAsk(request) }
        let renames = await persist()
        for case .view(let block, let form, let groupBy) in ops { changeView(of: block, to: form, groupBy: groupBy) }
        host.send(.ack(seq: seq, renames: renames))
        problem = capture { try refresh() } ?? problem
    }

    /// The blocks of the document that the person deleted, put back where they stood. The head is the machine's, not the person's.
    private func restore(_ blocks: DocumentBlocks, after ops: [EditorOp]) -> [PageChange] {
        let deleted = Set(ops.compactMap { op -> String? in if case .delete(let id) = op { id } else { nil } })
        let lastOfPage = model.order.last { !blocks.ids.contains($0) }
        return [(blocks.head, nil), (blocks.tail, lastOfPage)].flatMap { group, start in
            group.enumerated().compactMap { index, block -> PageChange? in
                deleted.contains(block.id)
                    ? .insert(after: index > 0 ? group[index - 1].id : start, block: shownBlocks[block.id] ?? block)
                    : nil
            }
        }
    }

    /// The person changed the words of a field. The editor holds them now; Swift reads what they mean.
    private func change(field id: String, to text: String) {
        guard case .field(_, let look, let hint, _)? = shownBlocks[id] else { return }
        shownBlocks[id] = .field(id: id, look: look, hint: hint, text: text)
        onField(id, text)
    }

    /// The person chose another form or group field for a facts view. The gate decides; a choice it refuses changes
    /// nothing. The changed block is the person's own edit: a new live row in the old one's place.
    private func changeView(of id: String, to form: String, groupBy: String) {
        guard let block = MachineBlockID(id), let form = FactsView.Form(rawValue: form) else { return }
        problem =
            capture {
                let contents = try store.queries.page(of: page, for: viewer)
                guard case .facts(let view)? = contents.page.blocks[block],
                    let changed = try views().changed(view, to: form, groupBy: groupBy)
                else { return }
                try store.replaceBlock(block, with: .facts(changed))
            } ?? problem
    }

    /// Saves until the store holds the page. A write that fails leaves nothing in the store, so it is tried again.
    private func persist() async -> [BlockRename] {
        var renames: [BlockRename] = []
        while !Task.isCancelled {
            do {
                renames += try await saveNote()
                try removeMachineBlocks()
                problem = nil
                return renames
            } catch {
                problem = "Could not save this page. Your words are still here. Workbench will try again."
                try? await Task.sleep(for: .seconds(2))
            }
        }
        return renames
    }

    private func saveNote() async throws -> [BlockRename] {
        var renames: [BlockRename] = []
        while let change = model.pendingChange(of: note) {
            guard let owner else { return renames }
            let report = try await store.saveNote(change, owner: owner)
            storeWrites += 1
            model.didSave(change)
            guard report.refusedAfterRevoke > 0 else { continue }
            let held = Set(try store.queries.noteBlocks(of: note).map(\.id))
            for refused in change.blocks.map(\.id) where !held.contains(refused) {
                let new = BlockID().rawValue
                model.rename(refused.rawValue, to: new)
                renames.append(BlockRename(from: refused.rawValue, to: new))
            }
        }
        return renames
    }

    private func removeMachineBlocks() throws {
        for block in model.removedMachines {
            do { try store.removeBlock(block, surface: .machinePage) } catch PageStoreError.notLive {}
        }
        model.didRemoveMachines()
    }

    private func capture(_ work: () throws -> Void) -> String? {
        do {
            try work()
            return nil
        } catch {
            return "Could not read this page: \(error.localizedDescription)"
        }
    }
}
