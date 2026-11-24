import Foundation
import WorkbenchCore

/// How a machine block stands on the page the person looks at.
enum BlockStanding: Equatable {
    case live
    /// A block a pending proposal brings in.
    case added
    /// A block a pending proposal puts in the place of one that is live.
    case replacement
    /// A live block a pending proposal takes out. It stays in its place until the person decides.
    case removed
}

struct ShownBlock: Equatable {
    var block: MachineBlock
    var standing: BlockStanding
    var isErased: Bool
}

/// The page as the person sees it: the live page with the pending proposal worked in, in one order.
struct ShownPage: Equatable {
    private(set) var order: [PageBlockRef]
    private(set) var blocks: [MachineBlockID: ShownBlock] = [:]
    /// The live block each replacement stands in the place of.
    private var replaced: [MachineBlockID: MachineBlockID] = [:]

    init(contents: PageContents, proposal: PendingProposal?) {
        order = contents.page.order
        for (id, block) in contents.page.blocks {
            blocks[id] = ShownBlock(block: block, standing: .live, isErased: contents.erased.contains(id))
        }
        if let proposal {
            for operation in proposal.operations { apply(operation, of: proposal) }
        }
    }

    /// The live block the store holds at the place of a shown block: the block itself, the block a replacement
    /// stands in for, or none for a block a proposal brings in.
    func liveBlock(at shown: MachineBlockID) -> MachineBlockID? {
        switch blocks[shown]?.standing {
        case .live, .removed: shown
        case .replacement: replaced[shown]
        case .added, nil: nil
        }
    }

    private mutating func apply(_ operation: StoredOperation, of proposal: PendingProposal) {
        switch operation {
        case .insert(let id, let after):
            guard let block = proposal.blocks[id] else { return }
            let place = after.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? order.count
            order.insert(.machine(id), at: place)
            blocks[id] = ShownBlock(block: block, standing: .added, isErased: proposal.erased.contains(id))
        case .replace(let old, let new):
            guard let block = proposal.blocks[new], let place = order.firstIndex(of: .machine(old)) else { return }
            order[place] = .machine(new)
            blocks[old] = nil
            replaced[new] = old
            blocks[new] = ShownBlock(block: block, standing: .replacement, isErased: proposal.erased.contains(new))
        case .remove(let id): blocks[id]?.standing = .removed
        }
    }
}
