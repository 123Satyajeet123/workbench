import SwiftUI
import WorkbenchCore

struct ItemBoard: View {
    let model: HelperModel
    let field: String
    let expected: String

    var body: some View {
        if !silent.isEmpty { SilentPeople(names: silent, noun: model.spec.itemsNoun) }
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

    static func groups(of items: [Item], field: String, expected names: [String]) -> [String] {
        let named = Set(items.map { $0[field] })
        return names.filter(named.contains) + named.subtracting(names).sorted()
    }
}

struct SilentPeople: View {
    static let shown = 8

    let names: [String]
    let noun: String
    @State private var showsAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label {
                Text("No \(noun) from \(names.count) \(names.count == 1 ? "person" : "people")").fontWeight(.medium)
            } icon: {
                Image(systemName: "questionmark.circle").foregroundStyle(Tone.attention.color)
            }
            Text(Self.line(names, showsAll: showsAll)).foregroundStyle(.supporting).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if names.count > Self.shown {
                Button(showsAll ? "Show fewer" : "Show all \(names.count)") {
                    withAnimation(Motion.settle(reduceMotion: reduceMotion)) { showsAll.toggle() }
                }
                .buttonStyle(.ghost).foregroundStyle(.linkText).padding(.leading, -Space.s)
            }
        }
        .calloutBox(fillsWidth: true)
    }

    static func line(_ names: [String], showsAll: Bool) -> String {
        guard !showsAll, names.count > shown else { return names.formatted(.list(type: .and)) }
        return names.prefix(shown).joined(separator: ", ") + " and \(names.count - shown) more"
    }
}
