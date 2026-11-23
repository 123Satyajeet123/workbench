import Foundation

@testable import WorkbenchCore

extension World {
    var names: [BlockID: String] {
        Dictionary(uniqueKeysWithValues: paragraphs.enumerated().map { ($0.element, "p\($0.offset + 1)") })
    }

    /// The order of a page in short words: `p1` for a paragraph, the kind of a machine block, `*` after a block that
    /// lost its words.
    func describe(_ contents: PageContents) -> String {
        contents.page.order.map { place in
            switch place {
            case .note(let block): names[block] ?? "new"
            case .machine(let block): short(contents.page.blocks[block]) + (contents.erased.contains(block) ? "*" : "")
            }
        }.joined(separator: " ")
    }

    func short(_ block: MachineBlock?) -> String {
        switch block {
        case .heading(let text)?: "h(\(text))"
        case .text?: "text"
        case .facts?: "facts"
        case .grid?: "grid"
        case .picker?: "picker"
        case nil: "?"
        }
    }

    func describe(_ place: PageBlockRef?, in proposal: PendingProposal) -> String {
        switch place {
        case .note(let block)?: names[block] ?? "p?"
        case .machine(let block)?: short(proposal.blocks[block])
        case nil: "the end"
        }
    }

    func describe(_ operation: StoredOperation, in proposal: PendingProposal) -> String {
        switch operation {
        case .insert(let block, let after):
            "insert \(short(proposal.blocks[block])) after \(describe(after, in: proposal))"
        case .replace(let old, let new): "replace \(old.rawValue.prefix(4)) by \(short(proposal.blocks[new]))"
        case .remove(let block): "remove \(block.rawValue.prefix(4))"
        }
    }
}
