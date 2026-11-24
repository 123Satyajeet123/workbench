import Foundation

@testable import WorkbenchCore

/// What a check may read: the page before the request, the facts, and the proposal. It holds no model prose beyond
/// `proposal.note`, which a check may test only for being empty.
struct PageEvalOutcome {
    let start: PageContents
    let facts: [Item]
    let proposal: PageProposal

    var result: MachinePage { proposal.page }

    /// The machine blocks of the resulting page, in page order.
    var blocks: [(id: MachineBlockID, block: MachineBlock)] {
        result.order.compactMap { place in
            guard case .machine(let id) = place, let block = result.blocks[id] else { return nil }
            return (id, block)
        }
    }

    /// The blocks that the page did not have, or that are not what they were.
    var changedBlocks: [MachineBlock] {
        blocks.filter { start.page.blocks[$0.id] != $0.block }.map(\.block)
    }

    var factsViews: [FactsView] { blocks.compactMap { if case .facts(let view) = $0.block { view } else { nil } } }
    var grids: [Grid] { blocks.compactMap { if case .grid(let grid) = $0.block { grid } else { nil } } }
    var changedTexts: [CitedText] { changedBlocks.compactMap { if case .text(let text) = $0 { text } else { nil } } }
    var changedPickers: [PickerKind] {
        changedBlocks.compactMap { if case .picker(let kind) = $0 { kind } else { nil } }
    }

    var personBlocks: [PageBlockRef] { result.order.filter { if case .note = $0 { true } else { false } } }
    var startPersonBlocks: [PageBlockRef] { start.page.order.filter { if case .note = $0 { true } else { false } } }

    var refusals: [PageRefusal] { proposal.verdicts.compactMap(\.refusal) }

    /// The blocks of the resulting page that the page did not have.
    var newBlocks: [MachineBlock] { result.blocks.filter { start.page.blocks[$0.key] == nil }.map(\.value) }

    /// The block of the starting page that is a facts view of this title.
    func startBlockID(titled title: String) -> MachineBlockID? {
        start.page.blocks.first { if case .facts(let view) = $0.value { view.title == title } else { false } }?.key
    }

    /// The facts view that stands at this place of the resulting page; nil for a paragraph, another kind or no place.
    func factsView(atPlace index: Int) -> FactsView? {
        guard result.order.indices.contains(index), case .machine(let id) = result.order[index],
            case .facts(let view)? = result.blocks[id]
        else { return nil }
        return view
    }
}
