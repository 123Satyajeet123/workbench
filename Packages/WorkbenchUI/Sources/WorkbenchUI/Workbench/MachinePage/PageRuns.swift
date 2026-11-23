import Foundation
import WorkbenchCore

/// One thing the page column draws, top to bottom.
enum PageSlot: Hashable {
    /// The paragraphs of the person between two machine blocks, as one text.
    case run(Int)
    case machine(MachineBlockID)
}

/// How the paragraphs of a note fall between the machine blocks of the page. The note is one document; machine
/// blocks stand between its paragraphs. Run `k` is the paragraphs after machine block `k - 1` and before block `k`,
/// and `sizes[k]` counts them in the document's order.
struct PageRuns: Equatable {
    private(set) var sizes: [Int]

    /// A paragraph the page names goes to its run. A paragraph it does not name, one the person is still writing,
    /// follows the paragraph before it; at the end of the note it goes to the last run, where the store puts a new
    /// paragraph. No paragraph goes to an earlier run than the one before it.
    init(order: [PageBlockRef], documentBlocks: [BlockID]) {
        var runOf: [BlockID: Int] = [:]
        var run = 0
        for place in order {
            switch place {
            case .machine: run += 1
            case .note(let block): runOf[block] = run
            }
        }
        sizes = Array(repeating: 0, count: run + 1)
        let lastKnown = documentBlocks.lastIndex { runOf[$0] != nil }
        var current = 0
        for (index, block) in documentBlocks.enumerated() {
            if let known = runOf[block] {
                current = max(current, known)
            } else if lastKnown.map({ index > $0 }) ?? true {
                current = sizes.count - 1
            }
            sizes[current] += 1
        }
    }

    var lastRun: Int { sizes.count - 1 }

    /// The slots of a page: each run that has paragraphs, and each machine block.
    func slots(order: [PageBlockRef]) -> [PageSlot] {
        var slots: [PageSlot] = []
        var run = 0
        for place in order {
            guard case .machine(let id) = place else { continue }
            if sizes[run] > 0 { slots.append(.run(run)) }
            slots.append(.machine(id))
            run += 1
        }
        if sizes[run] > 0 { slots.append(.run(run)) }
        return slots
    }

    /// The order the person sees, to save: for each run, its paragraphs that are in `saving`, then the live block the
    /// store holds at the place of the machine block that follows it (`liveBlock`), when there is one. `order` is the
    /// page as shown and `documentBlocks` the document's.
    func pageOrder(
        order: [PageBlockRef], documentBlocks: [BlockID], saving: [BlockID],
        liveBlock: (MachineBlockID) -> MachineBlockID?
    ) -> [PageBlockRef] {
        let machine = order.compactMap { place -> MachineBlockID? in
            if case .machine(let id) = place { id } else { nil }
        }
        let kept = Set(saving)
        return sizes.indices.flatMap { run -> [PageBlockRef] in
            let paragraphs = documentBlocks[blocks(of: run)].filter(kept.contains).map(PageBlockRef.note)
            guard run < machine.count, let live = liveBlock(machine[run]) else { return paragraphs }
            return paragraphs + [.machine(live)]
        }
    }

    /// The paragraphs of `run`, as positions in the document's blocks.
    func blocks(of run: Int) -> Range<Int> {
        let start = sizes[..<run].reduce(0, +)
        return start..<(start + sizes[run])
    }

    mutating func resize(_ run: Int, by change: Int) { sizes[run] += change }
}

extension NoteDocument {
    /// Where the paragraphs in `range` start in the note's text, and the text they make.
    func text(of range: Range<Int>) -> (start: Int, text: String) {
        let before = blocks[..<range.lowerBound].reduce(0) { $0 + $1.text.utf16.count + 1 }
        return (before, blocks[range].map(\.text).joined(separator: "\n"))
    }
}
