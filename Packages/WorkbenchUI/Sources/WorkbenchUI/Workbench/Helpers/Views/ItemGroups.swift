import SwiftUI
import WorkbenchCore

/// One section per value of a choice field, in the choice's order, then any other value an item gives.
struct ItemGroups: View {
    let model: HelperModel
    let field: String

    var body: some View {
        let byValue = Dictionary(grouping: model.items) { $0[field] }
        ForEach(values, id: \.self) { value in
            let own = byValue[value, default: []]
            if !own.isEmpty {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("\(value.capitalized) · \(own.count)").textStyle(.headline)
                    ForEach(own) { ItemRow(model: model, item: $0, showsSpan: false, grouping: field) }
                }
                Divider()
            }
        }
    }

    private var values: [String] {
        let declared: [String] =
            model.spec.fields.first { $0.name == field }.map { field in
                if case .choice(let values) = field.kind { values } else { [] }
            } ?? []
        return declared + Set(model.items.map { $0[field] }).subtracting(declared).sorted()
    }
}
