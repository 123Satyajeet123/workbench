import Foundation

/// What Today and the People and Projects pages read from facts: fields a model filled (`asks`, `severity`), the due
/// time code resolved, and the founder's own marks. Code reads no words.
extension Item {
    /// Whether the field a mark names holds the mark's value.
    func carries(_ mark: HelperSpec.Attention.Mark?) -> Bool { mark.map { self[$0.field] == $0.value } ?? false }

    /// The due time the fact was opened with.
    public var openedDue: Due? { try? Coding.value(Due.self, from: self[Item.dueField]) }

    /// When the fact is due now: the time its latest `due_changed` event gave, else the one it was opened with.
    public var due: Due? { dueChanged ?? openedDue }

    /// The day the fact is due; nil when it has no due time.
    public var dueDay: WorkDay? { due?.day }

    /// Whether lists show it at `now`: not marked wrong, not hidden, not snoozed.
    public func isListed(at now: Date) -> Bool { state != .rejected && !isHidden(at: now) }

    public func isOpen(in lifecycle: HelperSpec.Lifecycle?, at now: Date) -> Bool {
        closed == nil && isListed(at: now) && lifecycle.map { $0.open.contains(self[$0.field]) } == true
    }
}

/// The facts of one person or one project.
public struct FactGroup: Sendable, Equatable, Identifiable {
    public var name: String
    /// Facts still open, the soonest due first, then the newest.
    public var open: [Item]
    /// The others: done, closed, decided, stated. The newest first.
    public var rest: [Item]

    public var id: String { name }
}

public enum FactGroups {
    /// The listed facts grouped by the value of `field`, groups with open facts first, then by name. A fact with no
    /// value in `field` belongs to no group.
    public static func make(
        _ facts: [Item], by field: String, lifecycle: HelperSpec.Lifecycle?, now: Date
    ) -> [FactGroup] {
        let named = Dictionary(grouping: facts.filter { $0.isListed(at: now) && !$0[field].isEmpty }) { $0[field] }
        let groups = named.map { name, items in
            let isOpen = { (item: Item) in item.isOpen(in: lifecycle, at: now) }
            return FactGroup(
                name: name, open: items.filter(isOpen).sorted(by: soonestThenNewest),
                rest: items.filter { !isOpen($0) }.sorted(by: newest))
        }
        return groups.sorted { ($0.open.isEmpty ? 1 : 0, $0.name) < ($1.open.isEmpty ? 1 : 0, $1.name) }
    }

    /// What a page shows for a day whose summaries are missing: the listed facts of the groups that have no summary,
    /// without one. Facts with no value in `field` come last, in a group with an empty name, so no fact is lost.
    public static func unsummarized(
        _ facts: [Item], by field: String, lifecycle: HelperSpec.Lifecycle?, summarized: Set<String>, now: Date
    ) -> [FactGroup] {
        let groups = make(facts, by: field, lifecycle: lifecycle, now: now).filter { !summarized.contains($0.name) }
        let unnamed = facts.filter { $0.isListed(at: now) && $0[field].isEmpty }.sorted(by: newest)
        return unnamed.isEmpty ? groups : groups + [FactGroup(name: "", open: [], rest: unnamed)]
    }

    private static func newest(_ a: Item, _ b: Item) -> Bool { (a.day, a.start) > (b.day, b.start) }

    private static func soonestThenNewest(_ a: Item, _ b: Item) -> Bool {
        switch (a.dueDay, b.dueDay) {
        case (let first?, let second?) where first != second: first < second
        case (_?, nil): true
        case (nil, _?): false
        default: newest(a, b)
        }
    }
}

extension Summary {
    /// What the scope is about, without the field: "Asha" for "person: Asha".
    public var subject: String {
        scope.split(separator: ": ", maxSplits: 1).last.map(String.init) ?? scope
    }

}

extension Summary.Line {
    /// Whether a line still has a fact to show: it leaves Today when every fact it cites was hidden or marked wrong.
    public func isShown(among listed: Set<Int64>) -> Bool { cites.contains(where: listed.contains) }
}
