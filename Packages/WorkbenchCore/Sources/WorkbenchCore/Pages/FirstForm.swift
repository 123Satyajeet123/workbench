import Foundation

/// The views a machine's page can start with, worked out from the structure of its facts alone: which fields group
/// them, how many values each field has, and which facts need the person. It reads no words and no machine's name.
public enum FirstForm {
    /// How many facts that need the person show before the rest fold: a list longer than this is not read as one.
    static let needsLimit = 5

    /// What needs the person first, when anything does; then one folded view for each of the first two fields that name
    /// a member or a label and have two or more values, counted by the machine's own state field; else sections by the
    /// first field with two or more fixed values; else a table.
    public static func views(of spec: HelperSpec, items: [Item], lens: FactsLens) -> [FactsView] {
        var views: [FactsView] = []
        if items.contains(where: { !lens.needs(of: $0).isEmpty }) {
            views.append(
                FactsView(
                    title: "Needs you", layout: .list, show: .needsAttention, order: .urgent, limit: needsLimit))
        }
        let counted = countField(of: spec, items: items)
        let namers = spec.fields.filter { $0.kind.isNaming && distinctValues($0.name, in: items) >= 2 }
        views += namers.prefix(2).map { field in
            FactsView(
                title: "By \(field.name)", groupBy: field.name, layout: .list,
                countBy: counted == field.name ? nil : counted, order: .urgent)
        }
        if namers.isEmpty {
            views.append(sectionsOrTable(of: spec, items: items))
        }
        return views
    }

    private static func sectionsOrTable(of spec: HelperSpec, items: [Item]) -> FactsView {
        let noun = spec.itemsNoun.prefix(1).uppercased() + spec.itemsNoun.dropFirst()
        guard let field = fixedFields(of: spec).first(where: { distinctValues($0.name, in: items) >= 2 })
        else { return FactsView(title: noun, layout: .table, columns: [spec.title, PageCatalog.quoteColumn]) }
        return FactsView(title: "\(noun) by \(field.name)", groupBy: field.name, layout: .list, order: .urgent)
    }

    /// The field each folded row counts by: the state field of the lifecycle when it has two values, else the first
    /// field with a fixed set of values and two or more of them in use.
    private static func countField(of spec: HelperSpec, items: [Item]) -> String? {
        let candidates = [spec.lifecycle?.field].compactMap { $0 } + fixedFields(of: spec).map(\.name)
        return candidates.first { distinctValues($0, in: items) >= 2 }
    }

    /// The fields with a fixed set of values, the ones whose values the spec gives a tone first: those say how a fact is
    /// judged, so a view by them tells the person more than a view by a plain label.
    private static func fixedFields(of spec: HelperSpec) -> [HelperSpec.Field] {
        let fixed = spec.fields.filter { $0.kind.fixedValues != nil }
        let judged = fixed.filter { field in (field.kind.fixedValues ?? []).contains { spec.tones[$0] != nil } }
        return judged + fixed.filter { field in !judged.contains { $0.name == field.name } }
    }

    private static func distinctValues(_ field: String, in items: [Item]) -> Int {
        Set(items.map { $0[field] }.filter { !$0.isEmpty }).count
    }
}

extension HelperSpec.Field.Kind {
    /// Whether the field's values name something that has facts: a member or a label.
    fileprivate var isNaming: Bool {
        switch self {
        case .member, .label: true
        case .text, .choice, .date, .time, .computed, .objectRef: false
        }
    }
}
