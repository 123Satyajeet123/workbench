import Foundation
import GRDB

/// The first morning list offers to clear the backlog: "mark everything older than N days as handled" (research P1
/// §3.2, Superhuman's "Get Me To Zero"). N is a setting.
public enum FirstRun {
    /// The default for N, the backlog cutoff of Superhuman (research P1 §3.2).
    public static let defaultDays = 7
    /// The outcome of a fact that the cutoff closes.
    public static let outcome = "handled"

    /// The open facts opened before the day `days` days before `today`.
    public static func older(_ facts: [Item], thanDays days: Int, today: WorkDay) -> [Item] {
        let cutoff = today.adding(days: -days)
        return facts.filter { $0.closed == nil && $0.day < cutoff }
    }
}

/// One bulk "handled", as the store keeps it.
public struct HandledBatch: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var at: Date
    public var surface: MarkSurface
    public var olderThanDays: Int
    public var cutoffDay: WorkDay
}

extension Store {
    /// Marks facts as handled in one bulk event of the person: a row of `handled_batch`, and one close of outcome
    /// `FirstRun.outcome` for each fact still open, tied to the row. Nothing is deleted. `reopenHandled` takes the
    /// batch back. Nil when no fact was open.
    @discardableResult
    public func markHandled(
        _ ids: [Int64], olderThanDays days: Int, cutoff: WorkDay, surface: MarkSurface
    ) throws -> HandledBatch? {
        try writer.write { db in
            let open = try ids.filter { try Queries.item(db, id: $0)?.closed == nil }
            guard !open.isEmpty else { return nil }
            let now = clock()
            try db.execute(
                sql: """
                    INSERT INTO handled_batch(recorded_at, actor, surface, older_than_days, cutoff_day)
                    VALUES (?, 'person', ?, ?, ?)
                    """, arguments: [now.stored, surface.rawValue, days, cutoff.description])
            let batch = db.lastInsertedRowID
            for id in open {
                try addEvent(
                    db, item: id, kind: .close, outcome: FirstRun.outcome, batch: batch, at: now, surface: surface)
            }
            return HandledBatch(id: batch, at: now, surface: surface, olderThanDays: days, cutoffDay: cutoff)
        }
    }

    /// Reopens each fact of a batch that its close still ends. A fact reopened or closed again since is left alone.
    public func reopenHandled(batch: Int64, surface: MarkSurface) throws {
        try writer.write { db in
            let ids = try Int64.fetchAll(
                db,
                sql: """
                    SELECT item_id FROM item_event closed WHERE batch_id = ? AND kind = 'close' AND NOT EXISTS (
                        SELECT 1 FROM item_event later WHERE later.item_id = closed.item_id AND later.id > closed.id
                            AND later.kind IN ('supersede','close','reopen','withdraw'))
                    ORDER BY item_id
                    """, arguments: [batch])
            for id in ids { try addEvent(db, item: id, kind: .reopen, at: clock(), surface: surface) }
        }
    }
}

extension Queries {
    /// The latest bulk "handled", if there is one.
    public func latestHandledBatch() throws -> HandledBatch? {
        try reader.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM handled_batch ORDER BY id DESC LIMIT 1").map {
                HandledBatch(
                    id: $0["id"], at: try $0.date("recorded_at"), surface: try $0.enumeration("surface"),
                    olderThanDays: $0["older_than_days"], cutoffDay: try $0.workDay("cutoff_day"))
            }
        }
    }

    /// The facts that have a timer that fired and that nobody cancelled since: an open fact whose time has come.
    public func itemsWithFiredTimers() throws -> Set<Int64> {
        try reader.read { db in
            Set(
                try Int64.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT timer.item_id FROM timer
                        JOIN timer_fired ON timer_fired.timer_id = timer.id AND timer_fired.window_key = timer.fire_at
                        WHERE timer.cancelled_by_event IS NULL AND timer_fired.outcome = 'fired'
                        """))
        }
    }
}
