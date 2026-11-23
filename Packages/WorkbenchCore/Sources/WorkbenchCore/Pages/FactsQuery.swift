import Foundation

extension FactsView {
    public struct Section: Equatable, Sendable {
        /// The value of the grouping field; empty for a view with one section.
        public var name: String
        public var facts: [Item]
    }

    /// The facts the view shows: those whose fields have a value each filter allows.
    public func facts(in items: [Item]) -> [Item] {
        items.filter { item in
            filters.allSatisfy { field, values in values.isEmpty || values.contains(item[field]) }
        }
    }

    /// The shown facts by the value of the grouping field, in the order the values first appear.
    public func sections(in items: [Item]) -> [Section] {
        let shown = facts(in: items)
        guard let groupBy else { return [Section(name: "", facts: shown)] }
        return shown.reduce(into: [Section]()) { sections, item in
            if let index = sections.firstIndex(where: { $0.name == item[groupBy] }) {
                sections[index].facts.append(item)
            } else {
                sections.append(Section(name: item[groupBy], facts: [item]))
            }
        }
    }
}
