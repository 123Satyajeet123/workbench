import Foundation

extension FactsView {
    public struct Section: Equatable, Sendable {
        /// The value of the grouping field; empty for a view with one section.
        public var name: String
        public var facts: [Item]
    }

    /// The facts the view holds: those whose fields have a value each filter allows, and that `show` lets through.
    public func facts(in items: [Item], lens: FactsLens) -> [Item] {
        items.filter { item in
            filters.allSatisfy { field, values in values.isEmpty || values.contains(item[field]) }
                && passes(item, lens)
        }
    }

    private func passes(_ item: Item, _ lens: FactsLens) -> Bool {
        switch show {
        case .all: true
        case .open: lens.isOpen(item)
        case .needsAttention: !lens.needs(of: item).isEmpty
        }
    }

    /// The held facts by the value of the grouping field. In `stored` order the sections stand as their values first
    /// appear. In `urgent` order the facts of a section run by urgency, and the sections that hold what needs the
    /// person come first, each group in the field's own order when it has one.
    public func sections(in items: [Item], lens: FactsLens) -> [Section] {
        let held = facts(in: items, lens: lens)
        let ordered = order == .urgent ? held.sorted(by: lens.isMoreUrgent) : held
        guard let groupBy else { return [Section(name: "", facts: ordered)] }
        let sections = ordered.reduce(into: [Section]()) { sections, item in
            if let index = sections.firstIndex(where: { $0.name == item[groupBy] }) {
                sections[index].facts.append(item)
            } else {
                sections.append(Section(name: item[groupBy], facts: [item]))
            }
        }
        return order == .urgent ? Self.byUrgency(sections, groupedBy: groupBy, lens: lens) : sections
    }

    private static func byUrgency(_ sections: [Section], groupedBy field: String, lens: FactsLens) -> [Section] {
        let declared = lens.spec.fields.first { $0.name == field }?.kind.fixedValues ?? []
        func key(_ section: Section) -> (Int, Int, Int, String) {
            let needing = section.facts.filter { !lens.needs(of: $0).isEmpty }.count
            return (needing > 0 ? 0 : 1, declared.firstIndex(of: section.name) ?? 0, -needing, section.name)
        }
        return sections.sorted { key($0) < key($1) }
    }
}
