import Foundation

/// What the founder does with a fact, or with the facts a summary line cites. Every action is a row in the event or
/// mark tables, so each can be taken back.
public enum ItemAction: Sendable, Hashable {
    /// Close it with an outcome of the machine's lifecycle.
    case done(outcome: String)
    /// Hide it. The fact was read right, so this counts as a right mark.
    case notRelevant
    /// Hide it. The fact was read wrong, so this counts as a rejected mark.
    case wrong
    /// Hide it until the start of a work day.
    case snooze(until: WorkDay)
}

extension HelperSpec.Lifecycle {
    /// How the founder closes an item by hand: the outcome the spec gives its value of `field`, else the first outcome.
    public func doneOutcome(of item: Item) -> String {
        doneOutcomes?[item[field]].flatMap { outcomes.contains($0) ? $0 : nil } ?? outcomes.first ?? "kept"
    }

    /// The closes that finish `items`: each one still open gets its own outcome; one that is not open is left alone.
    public func closing(_ items: [Item]) -> [ItemAction: [Int64]] {
        var plan: [ItemAction: [Int64]] = [:]
        for item in items where item.closed == nil && open.contains(item[field]) {
            guard let id = item.id else { continue }
            plan[.done(outcome: doneOutcome(of: item)), default: []].append(id)
        }
        return plan
    }
}
