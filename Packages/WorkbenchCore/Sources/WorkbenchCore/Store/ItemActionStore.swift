import Foundation
import GRDB

extension Store {
    public func apply(_ action: ItemAction, to items: [Int64]) throws {
        try apply([action: items])
    }

    public func undo(_ action: ItemAction, on items: [Int64]) throws {
        try undo([action: items])
    }

    public func apply(_ plan: [ItemAction: [Int64]]) throws {
        try writer.write { db in
            for (action, items) in plan {
                for id in items { try apply(action, to: id, db) }
            }
        }
    }

    public func undo(_ plan: [ItemAction: [Int64]]) throws {
        try writer.write { db in
            for (action, items) in plan {
                for id in items { try undo(action, on: id, db) }
            }
        }
    }

    private func apply(_ action: ItemAction, to id: Int64, _ db: Database) throws {
        switch action {
        case .done(let outcome): try addEvent(db, item: id, kind: "close", outcome: outcome, at: clock())
        case .notRelevant:
            try addMark(db, item: id, .confirmed)
            try addEvent(db, item: id, kind: "hide", at: clock())
        case .wrong:
            try addMark(db, item: id, .rejected)
            try addEvent(db, item: id, kind: "hide", at: clock())
        case .snooze(let day): try addEvent(db, item: id, kind: "snooze", until: day.start, at: clock())
        }
    }

    private func undo(_ action: ItemAction, on id: Int64, _ db: Database) throws {
        switch action {
        case .done: try addEvent(db, item: id, kind: "reopen", at: clock())
        case .notRelevant, .wrong:
            try addMark(db, item: id, .proposed)
            try addEvent(db, item: id, kind: "unhide", at: clock())
        case .snooze: try addEvent(db, item: id, kind: "unhide", at: clock())
        }
    }
}
