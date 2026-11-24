import EditorHarness
import Foundation
import Kernel
import PageSnapshot

@testable import WorkbenchCore

/// One invented fact before it is stored: its words, its fields, how many days back it was read, when it falls due
/// (days from today, negative for late), and how it closed. Nothing here is a real person's name or a real message.
struct InventedFact {
    var quote: String
    var fields: [String: String]
    var daysAgo = 0
    var dueInDays: Int?
    var closedAs: String?
}

/// Saves invented facts through the synthetic-facts helper into a store, then gives them the day, the due
/// time and the close the helper cannot set. The facts come back as the store holds them.
@MainActor
func seed(_ invented: [InventedFact], in store: Store, of machine: Machine, owner: PersonID, scope: String) throws
    -> [Item]
{
    let stored = try saveSyntheticFacts(
        in: store, of: machine, owner: owner, scope: scope, sources: invented.map(\.quote),
        quotes: invented.map(\.quote), fields: invented.map(\.fields))
    let today = WorkDay(containing: Date())
    return try zip(stored, invented).map { fact, source in
        var item = fact
        item.day = today.adding(days: -source.daysAgo)
        if let due = source.dueInDays {
            item.fields[Item.dueField] = try Coding.json(Due.stated(on: today.adding(days: due)))
        }
        item.closed = source.closedAs.map { Item.Closed(outcome: $0, quote: nil, at: Date()) }
        return item
    }
}
