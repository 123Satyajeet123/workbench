import WorkbenchCore

@testable import WorkbenchUI

/// The page as short lines, one per block in the page's order: what the person reads, in words a log can hold.
extension MachinePageModel {
    var lines: [String] {
        shown.order.map { place in
            switch place {
            case .note(let id): "paragraph: \(paragraphText(id))"
            case .machine(let id): shown.blocks[id].map(Self.describe) ?? "missing block"
            }
        }
    }

    var paragraphs: [String] { editor.document.blocks.map(\.text).filter { !$0.isEmpty } }

    var textBlocks: [CitedText] {
        shown.blocks.values.compactMap { shownBlock in
            if case .text(let cited) = shownBlock.block { cited } else { nil }
        }
    }

    var firstMachineBlock: MachineBlockID? {
        shown.order.lazy.compactMap { if case .machine(let id) = $0 { id } else { nil } }.first
    }

    /// One line for a proposed operation, with the block it names as the page would show it.
    func describe(_ operation: StoredOperation) -> String {
        func block(_ id: MachineBlockID) -> String { shown.blocks[id].map(Self.describe) ?? "block not shown" }
        return switch operation {
        case .insert(let id, _): "insert \(block(id))"
        case .replace(let old, let new): "replace \(block(old)) with \(block(new))"
        case .remove(let id): "remove \(block(id))"
        }
    }

    private func paragraphText(_ id: BlockID) -> String {
        editor.document.blocks.first { $0.id == id }?.text ?? "(unknown paragraph)"
    }

    private static func describe(_ shownBlock: ShownBlock) -> String {
        let erased = shownBlock.isErased ? ", erased" : ""
        return "machine block [\(shownBlock.standing)\(erased)]: \(describe(shownBlock.block))"
    }

    private static func describe(_ block: MachineBlock) -> String {
        switch block {
        case .heading(let words): "heading \"\(words)\""
        case .text(let cited): "text \"\(cited.text)\" cites \(describe(cited.cites))"
        case .facts(let view): "facts view \"\(view.title)\" as \(view.layout.rawValue)"
        case .grid(let grid): "grid \"\(grid.title)\" \(grid.columns.count) columns, \(grid.rows.count) rows"
        case .picker(let kind): "picker \(kind.rawValue)"
        }
    }

    static func describe(_ cites: [PageCite]) -> String {
        cites.map { cite in
            switch cite {
            case .fact(let id): "fact \(id)"
            case .note: "paragraph"
            case .request: "request"
            }
        }.joined(separator: ", ")
    }
}
