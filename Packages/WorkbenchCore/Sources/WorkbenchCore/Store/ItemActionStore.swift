import Foundation
import GRDB

extension Store {
    /// Does `action` to every item.
    public func apply(_ action: ItemAction, to items: [Int64]) throws {
        try apply([action: items])
    }

    public func undo(_ action: ItemAction, on items: [Int64]) throws {
        try undo([action: items])
    }

    /// Does each action to its items, all in one transaction: a failure changes none. A hide, a wrong and a
    /// not-relevant keep the item on its machine's own page, shown as hidden; only the Today, People and Projects
    /// lists leave it out.
    public func apply(_ plan: [ItemAction: [Int64]]) throws {
        try writer.write { db in
            for (action, items) in plan {
                for id in items { try apply(action, to: id, db) }
            }
        }
    }

    /// Takes the actions back: a done is reopened, and the others are shown again. A mark that an action made is
    /// taken back too (marked as proposed).
    public func undo(_ plan: [ItemAction: [Int64]]) throws {
        try writer.write { db in
            for (action, items) in plan {
                for id in items { try undo(action, on: id, db) }
            }
        }
    }

    private func apply(_ action: ItemAction, to id: Int64, _ db: Database) throws {
        switch action {
        case .done(let outcome): try addEvent(db, item: id, kind: .close, outcome: outcome, at: clock())
        case .notRelevant:
            try addMark(db, item: id, .confirmed)
            try addEvent(db, item: id, kind: .hide, at: clock())
        case .wrong:
            try addMark(db, item: id, .rejected)
            try addEvent(db, item: id, kind: .hide, at: clock())
        case .snooze(let day): try addEvent(db, item: id, kind: .snooze, until: day.start, at: clock())
        }
    }

    private func undo(_ action: ItemAction, on id: Int64, _ db: Database) throws {
        switch action {
        case .done: try addEvent(db, item: id, kind: .reopen, at: clock())
        case .notRelevant, .wrong:
            try addMark(db, item: id, .proposed)
            try addEvent(db, item: id, kind: .unhide, at: clock())
        case .snooze: try addEvent(db, item: id, kind: .unhide, at: clock())
        }
    }
}
