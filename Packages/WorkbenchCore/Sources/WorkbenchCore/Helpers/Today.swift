import Foundation

/// What Today and the People and Projects pages read from facts: fields a model filled (`asks`, `eta`, `severity`)
/// and the founder's own marks. Code reads no words.
extension Item {
    /// The fact asks the founder for something, or waits on them.
    public var asksFounder: Bool { self["asks"] == "founder" }

    /// The day the fact is due, when its `eta` holds a date.
    public var dueDay: WorkDay? { WorkDay(self["eta"]) }

    /// Whether lists show it at `now`: not marked wrong, not hidden, not snoozed.
    public func isListed(at now: Date) -> Bool { state != .rejected && !isHidden(at: now) }
}

/// One line of Today's "Needs you": an open fact or a finding, and why it is there.
public struct Need: Sendable, Equatable, Identifiable {
    public enum Reason: Sendable, Equatable {
        /// A finding of the derailment watch that asks the founder to act today.
        case act
        /// A finding worth a look soon.
        case watch
        /// An open fact that asks the founder.
        case asks
        /// An open fact due on this day or before it.
        case due(WorkDay)
    }

    public var item: Item
    public var reason: Reason

    public var id: Int64? { item.id }
}

public enum Needs {
    /// What needs the founder, most urgent first: findings that ask for action, facts that ask the founder, facts
    /// due today or earlier, then findings to watch. A closed, hidden, snoozed or wrong item is left out.
    public static func pick(facts: [Item], findings: [Item], today: WorkDay, now: Date) -> [Need] {
        let open = facts.filter { $0.closed == nil && $0.isListed(at: now) }
        let listed = findings.filter { $0.closed == nil && $0.isListed(at: now) }
        let act = listed.filter { $0["severity"] == "act" }.map { Need(item: $0, reason: .act) }
        let watch = listed.filter { $0["severity"] == "watch" }.map { Need(item: $0, reason: .watch) }
        let asks = open.filter(\.asksFounder).map { Need(item: $0, reason: .asks) }
        let due = open.filter { !$0.asksFounder }.compactMap { fact in
            fact.dueDay.flatMap { $0 <= today ? (day: $0, need: Need(item: fact, reason: .due($0))) : nil }
        }
        return act + asks + due.sorted { $0.day < $1.day }.map(\.need) + watch
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
            let isOpen = { (item: Item) in
                item.closed == nil && lifecycle.map { $0.open.contains(item[$0.field]) } == true
            }
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
