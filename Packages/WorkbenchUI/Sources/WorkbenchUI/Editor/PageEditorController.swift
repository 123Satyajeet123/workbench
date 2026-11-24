import Foundation
import Kernel
import WorkbenchCore

/// Joins the stored page of a machine to the editor. It shows the page to the editor, turns the person's ops into
/// store calls, and shows what the store changed in answer. Swift is the one writer: the editor holds only a view of
/// the committed page and the person's own typing.
///
/// A paragraph of the person is one line of the note, kept under the id the editor gives it; its machine blocks stay
/// where the person put them. A block the person deletes is erased with its lines.
final class PageEditorController {
    private let store: Store
    private let note: NoteID
    private let page: WorkObjectID
    private let owner: PersonID
    private let viewer: PageViewer
    private let host: EditorHost
    private let views: () throws -> MachineViewBuilder
    private(set) var model: PageModel
    private var machineViews: [String: MachineView] = [:]
    private var environment: EditorEnvironment
    private var processing: Task<Void, Never>?
    private var idles = 0

    /// How many times the page wrote the store: the checks watch it.
    private(set) var storeWrites = 0
    private(set) var blockedLoads: [EditorMessage] = []
    /// Why the last save failed, in words for the person. The words stay in the editor and are saved again.
    private(set) var problem: String?
    var onMark: (Int64, FactMark) -> Void = { _, _ in }
    var onOpen: (OpenTarget) -> Void = { _ in }

    init(
        store: Store, page: WorkObjectID, owner: PersonID, host: EditorHost, appearance: EditorEnvironment.Appearance,
        reduceMotion: Bool, views: @escaping () throws -> MachineViewBuilder
    ) throws {
        guard let note = NoteID(object: page) else { throw WorkObjectError.unknown(page) }
        self.store = store
        self.note = note
        self.page = page
        self.owner = owner
        self.host = host
        self.views = views
        viewer = try PageViewer(owner: owner)
        model = PageModel(contents: try store.queries.page(of: page, for: viewer))
        environment = EditorEnvironment(
            appearance: appearance, reduceMotion: reduceMotion, tokens: EditorTokens.resolved(for: appearance))
        host.onMessage = { [weak self] message in self?.receive(message) }
    }

    func start() { host.load() }

    func setAppearance(_ appearance: EditorEnvironment.Appearance, reduceMotion: Bool) {
        environment = EditorEnvironment(
            appearance: appearance, reduceMotion: reduceMotion, tokens: EditorTokens.resolved(for: appearance))
        host.send(.environment(environment))
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

    /// Shows what the store holds now: blocks of machines that came, changed or left, and paragraphs that were erased
    /// elsewhere. What the person is typing stays.
    func refresh() throws {
        let contents = try store.queries.page(of: page, for: viewer)
        let builder = try views()
        var changes: [PageChange] = []
        let held = Set(contents.page.order.map(\.rawValue))
        for id in model.order where !held.contains(id) {
            let before = model.order.count
            model.forget(id)
            if model.order.count < before {
                machineViews[id] = nil
                changes.append(.remove(id: id))
            }
        }
        var previous: String?
        for place in contents.page.order {
            if case .machine(let block) = place, let stored = contents.page.blocks[block] {
                let id = block.rawValue
                let view = builder.view(of: stored, erased: contents.erased.contains(block))
                if model.machines.contains(id) {
                    if machineViews[id] != view { changes.append(.update(block: .machine(id: id, view: view))) }
                } else {
                    changes.append(.insert(after: previous, block: .machine(id: id, view: view)))
                    model.show(machine: id, after: previous)
                }
                machineViews[id] = view
            }
            if model.order.contains(place.rawValue) { previous = place.rawValue }
        }
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
        }
    }

    private func load() throws {
        let contents = try store.queries.page(of: page, for: viewer)
        let builder = try views()
        model = PageModel(contents: contents)
        machineViews = [:]
        let notes = Dictionary(uniqueKeysWithValues: contents.notes.map { ($0.id, $0.text) })
        let blocks = contents.page.order.compactMap { place -> PageBlockData? in
            switch place {
            case .note(let block): return notes[block].map { .note(id: block.rawValue, text: $0) }
            case .machine(let block):
                guard let stored = contents.page.blocks[block] else { return nil }
                let view = builder.view(of: stored, erased: contents.erased.contains(block))
                machineViews[block.rawValue] = view
                return .machine(id: block.rawValue, view: view)
            }
        }
        host.send(.load(blocks))
    }

    private func enqueue(_ work: @escaping () async -> Void) {
        let before = processing
        processing = Task {
            await before?.value
            await work()
        }
    }

    private func save(_ seq: Int, _ ops: [EditorOp]) async {
        model.apply(ops)
        for case .mark(let fact, let mark) in ops { onMark(fact, mark) }
        let renames = await persist()
        host.send(.ack(seq: seq, renames: renames))
        problem = capture { try refresh() } ?? problem
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

extension PageBlockRef {
    fileprivate var rawValue: String {
        switch self {
        case .note(let block): block.rawValue
        case .machine(let block): block.rawValue
        }
    }
}
