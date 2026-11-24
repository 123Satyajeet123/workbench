import Foundation
import WorkbenchCore

/// What a machine's blocks show, worked out here so the editor only draws it: the facts a view holds with their counts,
/// the answer of each formula, and the words of each chip. `titleOf` is the machine's own line for a fact with no quote.
struct MachineViewBuilder {
    var facts: [Item]
    var titleOf: (Item) -> String
    /// Why a picker cannot choose for this machine, in words for the person; nil when it can.
    var pickerNote: (PickerKind) -> String?

    static let erasedNote = "The message this came from was deleted"

    func view(of block: MachineBlock, erased: Bool) -> MachineView {
        guard !erased else { return .erased(note: Self.erasedNote) }
        switch block {
        case .heading(let words): return .heading(text: words)
        case .text(let cited): return .text(text: cited.text, cites: chips(cited.cites))
        case .facts(let view): return .facts(rendering(of: view))
        case .grid(let grid): return .grid(rendering(of: grid))
        case .picker(let kind): return .picker(rendering(of: kind))
        }
    }

    private func chips(_ cites: [PageCite]) -> [CiteChip] {
        cites.map { cite in
            switch cite {
            case .fact(let id):
                guard let item = facts.first(where: { $0.id == id }) else {
                    return CiteChip(ref: cite.reference, label: "A fact", opens: false)
                }
                return CiteChip(
                    ref: cite.reference, label: FactHeadline(item: item, title: titleOf(item)).plain, opens: true)
            case .note: return CiteChip(ref: cite.reference, label: "Your words", opens: false)
            case .request: return CiteChip(ref: cite.reference, label: "Your request", opens: false)
            }
        }
    }

    private func rendering(of view: FactsView) -> FactsRendering {
        let sections = view.sections(in: facts)
        let columns = view.columns.isEmpty ? [PageCatalog.quoteColumn] : view.columns
        return FactsRendering(
            title: view.title, layout: view.layout.rawValue,
            countText: Self.countText(sections.reduce(0) { $0 + $1.facts.count }), columns: columns,
            sections: sections.map { section in
                FactsRendering.Section(
                    name: section.name, countText: Self.countText(section.facts.count), count: section.facts.count,
                    rows: section.facts.compactMap { row(of: $0, columns: columns) })
            })
    }

    private func row(of item: Item, columns: [String]) -> FactsRendering.Row? {
        guard let id = item.id else { return nil }
        let headline = FactHeadline(item: item, title: titleOf(item))
        return FactsRendering.Row(
            fact: id, person: headline.person,
            words: headline.isQuote ? "\u{201C}\(headline.words)\u{201D}" : headline.words,
            cells: columns.map { column in
                let value = PageCatalog.value(of: column, in: item)
                return column == PageCatalog.quoteColumn ? "\u{201C}\(value)\u{201D}" : value
            })
    }

    private func rendering(of grid: WorkbenchCore.Grid) -> GridRendering {
        let values = grid.values
        return GridRendering(
            title: grid.title, columns: grid.columns,
            rows: grid.rows.indices.map { row in
                grid.columns.indices.map { cell(source: grid.rows[row][$0], value: values[row][$0]) }
            }, cites: chips(grid.cites))
    }

    private func cell(source: String, value: WorkbenchCore.Grid.Value) -> GridRendering.Cell {
        switch value {
        case .failed: GridRendering.Cell(text: "Cannot work this out", kind: "failed", source: source)
        case .number(let number) where source.hasPrefix("="):
            GridRendering.Cell(
                text: number.formatted(.number.precision(.fractionLength(0...2))), kind: "formula", source: source)
        case .number: GridRendering.Cell(text: source, kind: "number", source: source)
        case .words: GridRendering.Cell(text: source, kind: "words", source: source)
        }
    }

    private func rendering(of kind: PickerKind) -> PickerRendering {
        let note = pickerNote(kind)
        return PickerRendering(
            source: kind.rawValue, title: PickerBlockView.title(of: kind), note: note ?? "", available: note == nil)
    }

    static func countText(_ number: Int) -> String { number == 1 ? "1 fact" : "\(number) facts" }
}
