import SwiftUI
import WorkbenchCore

/// A small table a machine worked out. A formula cell shows its answer in a box, with the formula as its tooltip; a
/// formula that cannot be worked out shows a plain mark.
struct GridBlockView: View {
    let model: MachinePageModel
    let grid: WorkbenchCore.Grid

    var body: some View {
        CitedContent(model: model, cites: grid.cites) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(grid.title).text(.sectionTitle)
                table
            }
        }
    }

    private var table: some View {
        let values = grid.values
        return SwiftUI.Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.xs) {
            GridRow {
                ForEach(grid.columns.indices, id: \.self) { Text(grid.columns[$0]).text(.caption) }
            }
            Divider()
            ForEach(grid.rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(grid.columns.indices, id: \.self) { column in
                        GridCell(source: grid.rows[row][column], value: values[row][column])
                    }
                }
            }
        }
    }
}

private struct GridCell: View {
    let source: String
    let value: WorkbenchCore.Grid.Value

    var body: some View {
        switch value {
        case .failed:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Tone.bad.color)
                .help("This formula cannot be worked out: \(source)").accessibilityLabel(
                    "Formula that failed: \(source)")
        case .number(let number) where source.hasPrefix("="):
            Text(number.formatted(.number.precision(.fractionLength(0...2))))
                .textStyle(.body, weight: .semibold, digits: true)
                .padding(.horizontal, Space.xs).background(.selectedFill, in: .rect(cornerRadius: Radius.keyCap))
                .help(source).accessibilityLabel("\(number.formatted()), from the formula \(source)")
        case .number, .words: Text(source).textStyle(.body, digits: true)
        }
    }
}
