import SwiftUI
import WorkbenchCore

struct ItemGroups: View {
    let model: HelperModel
    let field: String

    var body: some View {
        let byValue = Dictionary(grouping: model.items) { $0[field] }
        ForEach(values, id: \.self) { value in
            let own = byValue[value, default: []]
            if !own.isEmpty {
                ItemSection(model: model, heading: "\(value.capitalized) · \(own.count)", items: own, field: field)
                Divider()
            }
        }
    }

    private var values: [String] {
        let declared = model.spec.fields.first { $0.name == field }?.kind.fixedValues ?? []
        return declared + Set(model.items.map { $0[field] }).subtracting(declared).sorted()
    }
}
