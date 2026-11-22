import SwiftUI
import WorkbenchCore

struct ItemSection<Accessory: View>: View {
    let model: HelperModel
    let heading: String
    let items: [Item]
    let field: String
    @ViewBuilder var accessory: (Item) -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(heading).textStyle(.headline)
            ForEach(items) { item in
                HStack(alignment: .top) {
                    ItemRow(model: model, item: item, showsSpan: false, grouping: field)
                    accessory(item)
                }
            }
        }
    }
}

extension ItemSection where Accessory == EmptyView {
    init(model: HelperModel, heading: String, items: [Item], field: String) {
        self.init(model: model, heading: heading, items: items, field: field) { _ in EmptyView() }
    }
}
