import Foundation

extension Item {
    public var asksFounder: Bool { self["asks"] == "founder" }

    public var dueDay: WorkDay? { WorkDay(self["eta"]) }

    public func isListed(at now: Date) -> Bool { state != .rejected && !isHidden(at: now) }

    public func isOpen(in lifecycle: HelperSpec.Lifecycle?, at now: Date) -> Bool {
        closed == nil && isListed(at: now) && lifecycle.map { $0.open.contains(self[$0.field]) } == true
    }
}

public struct Need: Sendable, Equatable, Identifiable {
    public enum Reason: Sendable, Equatable {
        case act
        case watch
        case asks
        case due(WorkDay)
    }

    public var item: Item
    public var reason: Reason

    public var id: Int64? { item.id }
}

public enum Needs {
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

public struct FactGroup: Sendable, Equatable, Identifiable {
    public var name: String
    public var open: [Item]
    public var rest: [Item]

    public var id: String { name }
}

public enum FactGroups {
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
    public var subject: String {
        scope.split(separator: ": ", maxSplits: 1).last.map(String.init) ?? scope
    }

}

extension Summary.Line {
    public func isShown(among listed: Set<Int64>) -> Bool { cites.contains(where: listed.contains) }
}
