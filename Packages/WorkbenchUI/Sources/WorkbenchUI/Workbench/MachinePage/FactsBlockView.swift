import SwiftUI
import WorkbenchCore

/// A view over the machine's facts, by its layout. Each fact is drawn by the fact card of the rest of the app, with
/// its own mark actions, so a mark made here is the mark made anywhere.
struct FactsBlockView: View {
    let model: MachinePageModel
    let view: FactsView
    @State private var inspected: Item?
    @Environment(\.uiScale) private var scale

    /// The width of one column of a board: a fact's words read as sentences at this width, whatever the number of
    /// columns. More columns than the page holds scroll sideways.
    private static let boardColumnWidth: CGFloat = 300

    var body: some View {
        let sections = view.sections(in: model.facts)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(view.title).text(.sectionTitle)
                Text(count(sections.reduce(0) { $0 + $1.facts.count })).text(.meta)
            }
            switch view.layout {
            case .list:
                ForEach(sections, id: \.name) { section in
                    SectionHeading(name: section.name)
                    FactRows(model: model, items: section.facts, inspected: $inspected)
                }
            case .board:
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Space.m) {
                        ForEach(sections, id: \.name) { section in
                            VStack(alignment: .leading, spacing: Space.s) {
                                SectionHeading(name: section.name)
                                FactRows(model: model, items: section.facts, inspected: $inspected)
                            }
                            .frame(width: Self.boardColumnWidth * scale, alignment: .topLeading)
                        }
                    }
                    .padding(.bottom, Space.m)
                }
            case .table:
                ForEach(sections, id: \.name) { section in
                    SectionHeading(name: section.name)
                    FactTable(model: model, columns: columns, items: section.facts)
                }
            case .counts:
                ForEach(sections, id: \.name) { section in
                    HStack {
                        Text(section.name.isEmpty ? "Facts" : section.name)
                        Spacer()
                        Text(section.facts.count.formatted()).textStyle(.body, digits: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let inspected { FactInspector(model: model, item: inspected) }
        }
    }

    private var columns: [String] { view.columns.isEmpty ? [PageCatalog.quoteColumn] : view.columns }

    private func count(_ number: Int) -> String { number == 1 ? "1 fact" : "\(number) facts" }
}

private struct SectionHeading: View {
    let name: String

    var body: some View {
        if !name.isEmpty { Text(name).text(.rowTitle).accessibilityAddTraits(.isHeader) }
    }
}

/// Fact cards, one under the other.
private struct FactRows: View {
    let model: MachinePageModel
    let items: [Item]
    @Binding var inspected: Item?
    @State private var hovered: Int64?

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items) { item in
                if let row = FactRow(item: item, title: item[model.spec.title]) {
                    FactCard(
                        row: row, offered: model.actions(for: item), isSelected: inspected?.id == row.id,
                        isHovered: hovered == row.id, wraps: true,
                        hover: { inside in hovered = inside ? row.id : (hovered == row.id ? nil : hovered) },
                        open: { inspected = inspected?.id == row.id ? nil : item },
                        act: { model.act($0, on: item) })
                }
            }
        }
    }
}

/// Facts as rows of the columns the view names. The column `quote` holds the exact words.
private struct FactTable: View {
    let model: MachinePageModel
    let columns: [String]
    let items: [Item]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Space.m, verticalSpacing: Space.s) {
            GridRow {
                ForEach(columns, id: \.self) { Text($0.capitalized).text(.caption) }
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            Divider()
            ForEach(items) { item in
                GridRow {
                    ForEach(columns, id: \.self) { column in
                        Group {
                            if column == PageCatalog.quoteColumn {
                                Text("“\(item.quote)”").text(.quote).textSelection(.enabled)
                            } else {
                                Text(PageCatalog.value(of: column, in: item)).textStyle(.body)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    MarkBar(actions: model.actions(for: item)) { model.act($0, on: item) }
                }
            }
        }
    }
}
