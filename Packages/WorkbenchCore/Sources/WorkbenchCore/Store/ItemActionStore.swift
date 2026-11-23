import Foundation
import GRDB

extension Store {
    /// Does `action` to every item, on `surface`.
    public func apply(_ action: ItemAction, to items: [Int64], surface: MarkSurface) throws {
        try apply([action: items], surface: surface)
    }

    public func undo(_ action: ItemAction, on items: [Int64], surface: MarkSurface) throws {
        try undo([action: items], surface: surface)
    }

    /// Does each action to its items, all in one transaction: a failure changes none. Each is an event of the person
    /// on `surface`. A hide, a wrong and a not-relevant keep the item on its machine's own page, shown as hidden; only
    /// the Today, People and Projects lists leave it out.
    public func apply(_ plan: [ItemAction: [Int64]], surface: MarkSurface) throws {
        try writer.write { db in
            for (action, items) in plan {
                for id in items { try apply(action, to: id, surface: surface, db) }
            }
        }
    }

    /// Takes the actions back: a done is reopened, a hand off is given back, and the others are shown again. A mark
    /// that an action made is taken back too (marked as proposed).
    public func undo(_ plan: [ItemAction: [Int64]], surface: MarkSurface) throws {
        try writer.write { db in
            for (action, items) in plan {
                for id in items { try undo(action, on: id, surface: surface, db) }
            }
        }
    }

    private func apply(_ action: ItemAction, to id: Int64, surface: MarkSurface, _ db: Database) throws {
        switch action {
        case .done(let outcome):
            try addEvent(db, item: id, kind: .close, outcome: outcome, at: clock(), surface: surface)
        case .notRelevant:
            try addMark(db, item: id, .confirmed)
            try addEvent(db, item: id, kind: .hide, at: clock(), surface: surface)
        case .wrong:
            try addMark(db, item: id, .rejected)
            try addEvent(db, item: id, kind: .hide, at: clock(), surface: surface)
        case .snooze(let day):
            try addEvent(db, item: id, kind: .snooze, until: day.start, at: clock(), surface: surface)
        case .handOff(let person):
            try addEvent(db, item: id, kind: .handOff, handedTo: person, at: clock(), surface: surface)
        }
    }

    private func undo(_ action: ItemAction, on id: Int64, surface: MarkSurface, _ db: Database) throws {
        switch action {
        case .done: try addEvent(db, item: id, kind: .reopen, at: clock(), surface: surface)
        case .notRelevant, .wrong:
            try addMark(db, item: id, .proposed)
            try addEvent(db, item: id, kind: .unhide, at: clock(), surface: surface)
        case .snooze: try addEvent(db, item: id, kind: .unhide, at: clock(), surface: surface)
        case .handOff: try addEvent(db, item: id, kind: .handOff, at: clock(), surface: surface)
        }
    }
}
