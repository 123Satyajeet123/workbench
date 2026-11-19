import SwiftUI
import WorkbenchCore

/// One section per value of a field. Every name the helper expects is shown, with a note when it has no item.
/// The items grouped by person: everyone with items first, then one line naming everyone the day has none from.
struct ItemBoard: View {
    let model: HelperModel
    let field: String
    let expected: String

    var body: some View {
        if !silent.isEmpty {
            Label(
                "No \(model.spec.itemsNoun) from \(silent.joined(separator: ", "))", systemImage: "questionmark.circle"
            )
            .foregroundStyle(Tone.attention.color)
        }
        let byGroup = Dictionary(grouping: model.items) { $0[field] }
        ForEach(groups, id: \.self) { group in
            VStack(alignment: .leading, spacing: Space.s) {
                Text(group).textStyle(.headline)
                ForEach(byGroup[group, default: []]) { ItemRow(model: model, item: $0, showsSpan: false) }
            }
            Divider()
        }
    }

    /// People with items: expected names in their order, then any other name an item gives.
    private var groups: [String] {
        let named = Set(model.items.map { $0[field] })
        let names = model.context[expected] ?? []
        return names.filter(named.contains) + named.subtracting(names).sorted()
    }

    private var silent: [String] {
        let named = Set(model.items.map { $0[field] })
        return (model.context[expected] ?? []).filter { !named.contains($0) }
    }
}
