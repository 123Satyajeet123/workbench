import Foundation
import WorkbenchCore

/// The page as the editor holds it: every block in order, the words of the person's paragraphs, and what the store
/// already has. The editor's ops change it; `pendingChange` is what the store must still be told. It touches no store.
struct PageModel: Equatable {
    private(set) var order: [String] = []
    private(set) var texts: [String: String] = [:]
    private(set) var machines: Set<String> = []
    private var saved: [String: String] = [:]
    private var savedOrder: [PageBlockRef] = []
    private var endings: [BlockEnding] = []
    private(set) var removedMachines: [MachineBlockID] = []

    /// The page as the store holds it.
    init(contents: PageContents) {
        for place in contents.page.order {
            switch place {
            case .note(let block): order.append(block.rawValue)
            case .machine(let block):
                order.append(block.rawValue)
                machines.insert(block.rawValue)
            }
        }
        for note in contents.notes {
            texts[note.id.rawValue] = note.text
            saved[note.id.rawValue] = note.text
        }
        savedOrder = contents.page.order
    }

    // MARK: What the person did

    mutating func apply(_ ops: [EditorOp]) {
        for op in ops { apply(op) }
    }

    private mutating func apply(_ op: EditorOp) {
        switch op {
        case .insert(let id, let after, let text):
            place(id, after: after)
            texts[id] = text
        case .update(let id, let text): texts[id] = text
        case .move(let id, let after):
            order.removeAll { $0 == id }
            place(id, after: after)
        case .delete(let id): end(id) { .deleted($0) }
        case .merge(let id, let into):
            end(id) { block in BlockID(into).map { .merged(block, into: $0) } ?? .deleted(block) }
        case .mark: break
        }
    }

    private mutating func end(_ id: String, _ ending: (BlockID) -> BlockEnding) {
        order.removeAll { $0 == id }
        if machines.remove(id) != nil {
            if let block = MachineBlockID(id) { removedMachines.append(block) }
            return
        }
        texts[id] = nil
        if let block = BlockID(id) { endings.append(ending(block)) }
    }

    private mutating func place(_ id: String, after: String?) {
        order.insert(id, at: after.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
    }

    // MARK: What Swift committed

    /// A block of a machine the store holds shows after `after`.
    mutating func show(machine id: String, after: String?) {
        guard !machines.contains(id) else { return }
        machines.insert(id)
        place(id, after: after)
    }

    /// A block the store no longer holds leaves the page. What the person wrote since the last save stays.
    mutating func forget(_ id: String) {
        let place = blockRef(id)
        guard machines.contains(id) || saved[id] == texts[id] else { return }
        machines.remove(id)
        order.removeAll { $0 == id }
        texts[id] = nil
        saved[id] = nil
        savedOrder.removeAll { $0 == place }
    }

    /// The store refused the name of a paragraph, because that block ended: it gets a new name.
    mutating func rename(_ id: String, to new: String) {
        guard let at = order.firstIndex(of: id) else { return }
        order[at] = new
        texts[new] = texts.removeValue(forKey: id)
        saved[id] = nil
    }

    // MARK: What the store must be told

    /// The change to save now, or nil when the store has this page.
    func pendingChange(of note: NoteID) -> NoteChange? {
        let live = order.compactMap { id in texts[id].flatMap { _ in BlockID(id) } }
        let changed = live.filter { saved[$0.rawValue] != texts[$0.rawValue] }
        let ended = resolvedEndings()
        let pageOrder = order.compactMap(blockRef)
        guard !changed.isEmpty || !ended.isEmpty || pageOrder != savedOrder else { return nil }
        return NoteChange(
            note: note, blocks: changed.map { NoteBlock(id: $0, text: texts[$0.rawValue] ?? "") }, endings: ended,
            order: live, pageOrder: pageOrder)
    }

    /// The store holds `change`.
    mutating func didSave(_ change: NoteChange) {
        for block in change.blocks { saved[block.id.rawValue] = block.text }
        for ending in change.endings { saved[ending.endedBlock.rawValue] = nil }
        savedOrder = change.pageOrder ?? savedOrder
        endings.removeAll()
    }

    mutating func didRemoveMachines() { removedMachines.removeAll() }

    private func blockRef(_ id: String) -> PageBlockRef? {
        if machines.contains(id) { return MachineBlockID(id).map(PageBlockRef.machine) }
        return texts[id] == nil ? nil : BlockID(id).map(PageBlockRef.note)
    }

    /// An ending the store can write: its block is in the store. A block joined into one that ended follows that one,
    /// and a block joined into words that were removed is deleted.
    private func resolvedEndings() -> [BlockEnding] {
        endings.compactMap { ending in
            guard saved[ending.endedBlock.rawValue] != nil else { return nil }
            guard case .merged(let block, let into) = ending else { return ending }
            return survivor(of: into.rawValue).map { .merged(block, into: $0) } ?? .deleted(block)
        }
    }

    private func survivor(of id: String) -> BlockID? {
        if let ending = endings.first(where: { $0.endedBlock.rawValue == id }) {
            guard case .merged(_, let into) = ending else { return nil }
            return survivor(of: into.rawValue)
        }
        return texts[id] == nil ? nil : BlockID(id)
    }
}

extension BlockEnding {
    fileprivate var endedBlock: BlockID {
        switch self {
        case .deleted(let block), .merged(let block, _): block
        }
    }
}
