import Foundation

/// A note as the editor holds it: its blocks in order, what the store already has, and how blocks ended since. The
/// editor reports each edit as a replaced range of the note's text, where one `\n` stands between two blocks. This type
/// decides from the edit which blocks keep their names, which are new and how each ended. It reads no text to guess:
/// the edit names everything.
public struct NoteDocument: Equatable, Sendable {
    public let note: NoteID
    public private(set) var blocks: [NoteBlock]
    private var saved: [BlockID: String]
    private var savedOrder: [BlockID]
    private var endings: [BlockEnding] = []

    /// A note with the blocks the store holds. With none, one empty block to write in.
    public init(note: NoteID, stored: [NoteBlock] = []) {
        self.note = note
        blocks = stored.isEmpty ? [NoteBlock(id: BlockID(), text: "")] : stored
        saved = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.text) })
        savedOrder = stored.map(\.id)
    }

    public var text: String { blocks.map(\.text).joined(separator: "\n") }

    public var hasUnsavedChanges: Bool { pendingChange() != nil }

    /// Applies one edit: `range` of the text, in UTF-16 units, is replaced by `replacement`.
    public mutating func replace(_ range: Range<Int>, with replacement: String, newID: () -> BlockID = { BlockID() }) {
        let start = place(of: range.lowerBound)
        let end = place(of: range.upperBound)
        if removesWholeBlocks(from: start, to: end, replacement) {
            endings += blocks[start.block..<end.block].map { .deleted($0.id) }
            blocks.removeSubrange(start.block..<end.block)
            return
        }
        let lines = replacement.components(separatedBy: "\n")
        let first = blocks[start.block]
        let tail = blocks[end.block].text.dropFirst(utf16: end.offset)
        var built = [NoteBlock(id: first.id, text: first.text.prefix(utf16: start.offset) + lines[0])]
        if lines.count == 1 {
            built[0].text += tail
        } else {
            built += lines.dropFirst().dropLast().map { NoteBlock(id: newID(), text: $0) }
            built.append(NoteBlock(id: newID(), text: lines[lines.count - 1] + tail))
        }
        if start.offset == 0, !first.isBlank, end.block > start.block || end.offset == first.text.utf16.count {
            endings.append(.deleted(first.id))
            built[0].id = newID()
        } else if start.block == end.block, built.count > 1, built[0].isBlank, !built[built.count - 1].isBlank {
            let kept = built[0].id
            built[0].id = built[built.count - 1].id
            built[built.count - 1].id = kept
        }
        let holder = lines.count == 1 ? built[0].id : built[built.count - 1].id
        if end.block > start.block {
            for index in (start.block + 1)...end.block {
                let removed = blocks[index]
                let onlyTheBreak = index == end.block && end.offset == 0 && !removed.isBlank
                endings.append(onlyTheBreak ? .merged(removed.id, into: holder) : .deleted(removed.id))
            }
        }
        for index in built.indices where built[index].isBlank && saved[built[index].id] != nil {
            endings.append(.deleted(built[index].id))
            built[index].id = newID()
        }
        blocks.replaceSubrange(start.block...end.block, with: built)
    }

    /// Whether the edit removes the blocks from `start` up to the one at `end` and nothing else: the person deleted
    /// whole paragraphs and the break after them. The block at `end` stays as it is.
    private func removesWholeBlocks(
        from start: (block: Int, offset: Int), to end: (block: Int, offset: Int), _ replacement: String
    )
        -> Bool
    {
        start.offset == 0 && end.offset == 0 && end.block > start.block && replacement.isEmpty
    }

    /// The block that holds this offset of the text.
    public func blockID(at offset: Int) -> BlockID { blocks[place(of: offset).block].id }

    /// Where a block starts in the text, in UTF-16 units.
    public func offset(of block: BlockID) -> Int {
        blocks.prefix { $0.id != block }.reduce(0) { $0 + $1.text.utf16.count + 1 }
    }

    /// Moves a block by `distance` places. Its name stays.
    public mutating func move(_ block: BlockID, by distance: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == block }) else { return }
        let target = min(max(index + distance, 0), blocks.count - 1)
        blocks.insert(blocks.remove(at: index), at: target)
    }

    /// The change to save now, or nil when the store already has this note.
    public func pendingChange() -> NoteChange? {
        let live = blocks.filter { !$0.isBlank }
        let changed = live.filter { saved[$0.id] != $0.text }
        let order = live.map(\.id)
        let ended = resolvedEndings()
        guard !changed.isEmpty || !ended.isEmpty || order != savedOrder else { return nil }
        return NoteChange(note: note, blocks: changed, endings: ended, order: order)
    }

    /// The store holds `change`. Edits made while it was written stay pending.
    public mutating func didSave(_ change: NoteChange) {
        for block in change.blocks { saved[block.id] = block.text }
        for ending in change.endings { saved[ending.block] = nil }
        savedOrder = change.order
        dropUnneededEndings()
    }

    /// The store no longer holds these blocks, because the person deleted the note elsewhere: they leave the document.
    /// What the person wrote since the last save stays.
    public mutating func drop(_ gone: Set<BlockID>) {
        blocks.removeAll { gone.contains($0.id) && saved[$0.id] == $0.text }
        for block in gone { saved[block] = nil }
        savedOrder.removeAll { gone.contains($0) }
        if blocks.isEmpty { blocks = [NoteBlock(id: BlockID(), text: "")] }
        dropUnneededEndings()
    }

    /// The ids of the blocks the store held at the last save.
    public var savedBlocks: Set<BlockID> { Set(saved.keys) }

    /// The store refused these blocks, because their names ended: they get new names and are saved again.
    public mutating func rename(_ refused: Set<BlockID>, newID: () -> BlockID = { BlockID() }) {
        for index in blocks.indices where refused.contains(blocks[index].id) {
            saved[blocks[index].id] = nil
            blocks[index].id = newID()
        }
    }

    /// An ending stays while the store holds its block, or while a kept ending merges into it.
    private mutating func dropUnneededEndings() {
        var needed: Set<BlockID> = []
        func need(_ block: BlockID) {
            guard needed.insert(block).inserted,
                case .merged(_, let into)? = endings.first(where: { $0.block == block })
            else { return }
            need(into)
        }
        for ending in endings where saved[ending.block] != nil { need(ending.block) }
        endings.removeAll { !needed.contains($0.block) }
    }

    private func place(of offset: Int) -> (block: Int, offset: Int) {
        var remaining = max(offset, 0)
        for (index, block) in blocks.enumerated() {
            let length = block.text.utf16.count
            if remaining <= length || index == blocks.count - 1 { return (index, min(remaining, length)) }
            remaining -= length + 1
        }
        return (0, 0)
    }

    /// The endings the store can write. A block the store never held has none. A block merged into one that ended
    /// before the save follows that one: into the block it joined, or, when the words were removed, deleted.
    private func resolvedEndings() -> [BlockEnding] {
        endings.compactMap { ending in
            guard saved[ending.block] != nil else { return nil }
            guard case .merged(let block, let into) = ending else { return ending }
            return survivor(of: into).map { .merged(block, into: $0) } ?? .deleted(block)
        }
    }

    private func survivor(of block: BlockID) -> BlockID? {
        if let ending = endings.first(where: { $0.block == block }) {
            guard case .merged(_, let into) = ending else { return nil }
            return survivor(of: into)
        }
        return blocks.first { $0.id == block && !$0.isBlank }?.id
    }
}

extension String {
    fileprivate func prefix(utf16 count: Int) -> String { String(self[..<index(utf16: count)]) }
    fileprivate func dropFirst(utf16 count: Int) -> String { String(self[index(utf16: count)...]) }
    private func index(utf16 offset: Int) -> Index { utf16.index(startIndex, offsetBy: offset) }
}
