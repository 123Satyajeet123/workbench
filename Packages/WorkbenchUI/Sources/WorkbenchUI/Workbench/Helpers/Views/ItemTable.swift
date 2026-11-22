import SwiftUI
import WorkbenchCore

/// One row per item: a column per field, then the quote it came from and the marks.
struct ItemTable: View {
    let model: HelperModel

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Space.m, verticalSpacing: Space.s) {
            GridRow {
                ForEach(model.spec.fields, id: \.name) { Text($0.name.capitalized) }
                Text("Quote")
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            .textStyle(.caption).foregroundStyle(.supporting)
            Divider()
            ForEach(model.items) { item in
                GridRow {
                    ForEach(model.spec.fields, id: \.name) { Text(item[$0.name]) }
                    Text(item.quotedWords).textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
                    HStack(spacing: Space.s) {
                        MarkButtons(state: item.state) { model.mark(item, as: $0) }
                        ItemActions(model: model, item: item)
                    }
                }
                .opacity(item.state == .rejected ? 0.5 : 1)
            }
        }
    }
}
