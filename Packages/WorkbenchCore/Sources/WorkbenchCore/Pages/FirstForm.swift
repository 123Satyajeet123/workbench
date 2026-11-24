import Foundation

/// The views a machine's page starts with, worked out from the structure of its spec alone: which fields name a member
/// or a label, which have a fixed set of values and which of those the spec gives a tone, and whether facts open and
/// close. It reads no words, no machine's name and no facts, so a page can start before the first fact is read.
public enum FirstForm {
    /// How many facts that need the person show before the rest fold: a list longer than this is not read as one.
    static let needsLimit = 5

    /// What needs the person first, for a machine whose facts open and close; then one folded view for each of the
    /// first two fields that name a member or a label, counted by the lifecycle field or the first toned field with a
    /// fixed set of values; else sections by that toned field; else a table of the machine's titles and quotes.
    public static func views(of spec: HelperSpec) -> [FactsView] {
        var views: [FactsView] = []
        if spec.lifecycle != nil {
            views.append(
                FactsView(
                    title: "Needs you", layout: .list, show: .needsAttention, order: .urgent, limit: needsLimit))
        }
        let counted = countField(of: spec)
        let namers = spec.fields.filter(\.kind.isNaming)
        views += namers.prefix(2).map { field in
            FactsView(
                title: FactsView.title(groupedBy: field.name), groupBy: field.name, layout: .list,
                countBy: counted == field.name ? nil : counted, order: .urgent)
        }
        if namers.isEmpty { views.append(sectionsOrTable(of: spec)) }
        return views
    }

    private static func sectionsOrTable(of spec: HelperSpec) -> FactsView {
        let noun = spec.itemsNoun.prefix(1).uppercased() + spec.itemsNoun.dropFirst()
        guard let field = fixedFields(of: spec).first else {
            return FactsView(title: noun, layout: .table, columns: [spec.title, PageCatalog.quoteColumn])
        }
        return FactsView(title: "\(noun) by \(field.name)", groupBy: field.name, layout: .list, order: .urgent)
    }

    /// The field each folded row counts by: the state field of the lifecycle, else the first fixed field.
    public static func countField(of spec: HelperSpec) -> String? {
        spec.lifecycle?.field ?? fixedFields(of: spec).first?.name
    }

    /// The fields with a fixed set of values, the ones whose values the spec gives a tone first: those say how a fact is
    /// judged, so a view by them tells the person more than a view by a plain label.
    private static func fixedFields(of spec: HelperSpec) -> [HelperSpec.Field] {
        let fixed = spec.fields.filter { $0.kind.fixedValues != nil }
        let judged = fixed.filter { field in (field.kind.fixedValues ?? []).contains { spec.tones[$0] != nil } }
        return judged + fixed.filter { field in !judged.contains { $0.name == field.name } }
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
