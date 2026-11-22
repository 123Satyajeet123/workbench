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
            ItemSection(model: model, heading: group, items: byGroup[group, default: []], field: field)
            Divider()
        }
    }

    private var groups: [String] { Self.groups(of: model.items, field: field, expected: model.context[expected] ?? []) }

    private var silent: [String] {
        let named = Set(model.items.map { $0[field] })
        return (model.context[expected] ?? []).filter { !named.contains($0) }
    }

    /// People with items: expected names in their order, then any other name an item gives.
    static func groups(of items: [Item], field: String, expected names: [String]) -> [String] {
        let named = Set(items.map { $0[field] })
        return names.filter(named.contains) + named.subtracting(names).sorted()
    }
}
