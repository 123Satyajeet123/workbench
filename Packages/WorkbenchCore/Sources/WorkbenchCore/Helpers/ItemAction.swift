import Foundation

public enum ItemAction: Sendable, Hashable {
    case done(outcome: String)
    case notRelevant
    case wrong
    case snooze(until: WorkDay)
}

extension HelperSpec.Lifecycle {
    public func doneOutcome(of item: Item) -> String {
        let resolves = item[field] == "blocker" && outcomes.contains("resolved")
        return resolves ? "resolved" : outcomes.first ?? "kept"
    }

    public func closing(_ items: [Item]) -> [ItemAction: [Int64]] {
        var plan: [ItemAction: [Int64]] = [:]
        for item in items where item.closed == nil && open.contains(item[field]) {
            guard let id = item.id else { continue }
            plan[.done(outcome: doneOutcome(of: item)), default: []].append(id)
        }
        return plan
    }
}
