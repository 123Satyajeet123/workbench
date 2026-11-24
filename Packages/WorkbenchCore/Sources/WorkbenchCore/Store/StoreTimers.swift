import Foundation
import GRDB

/// A timer that was decided: fired, or skipped as stale.
public struct FiredTimer: Sendable, Equatable {
    public var timer: Int64
    public var item: Int64
    public var kind: TimerRow.Kind
    public var fireAt: Date
    public var outcome: Timers.Outcome
}

extension TimerFact {
    init(_ item: Item) { self.init(task: item.task, fields: item.fields, opened: item.start, due: item.due) }
}

extension Store {
    /// Makes the timers of one fact match its state: the lifecycle calls it after it opens a fact and after each event
    /// that can change the state. An open fact has the timers `Timers.rows` gives. A fact that is closed, withdrawn or
    /// replaced has none: its timers are cancelled by the event that ended it. A new due time cancels the old timer
    /// and arms another. A reopened fact gets back the timers it had. A timer is never deleted.
    func reconcileTimers(_ db: Database, item id: Int64) throws {
        guard let item = try Queries.item(db, id: id) else { return }
        let desired = item.closed == nil ? Timers.rows(of: TimerFact(item), policies: try Queries.slaPolicies(db)) : []
        let latestEvent = try Int64.fetchOne(
            db, sql: "SELECT MAX(id) FROM item_event WHERE item_id = ?", arguments: [id])
        let stored = try Row.fetchAll(
            db,
            sql: "SELECT id, kind, fire_at, cancelled_by_event IS NOT NULL AS cancelled FROM timer WHERE item_id = ?",
            arguments: [id])
        let storedKeys = Set(stored.map { Self.timerKey(kind: $0["kind"], fireAt: $0["fire_at"]) })
        let desiredKeys = Set(desired.map { Self.timerKey(kind: $0.kind.rawValue, fireAt: $0.fireAt.stored) })
        for row in stored {
            let wanted = desiredKeys.contains(Self.timerKey(kind: row["kind"], fireAt: row["fire_at"]))
            let isCancelled: Bool = row["cancelled"]
            guard wanted == isCancelled else { continue }
            try db.execute(
                sql: "UPDATE timer SET cancelled_by_event = ? WHERE id = ?",
                arguments: [wanted ? nil : latestEvent, row["id"] as Int64])
        }
        for row in desired where !storedKeys.contains(Self.timerKey(kind: row.kind.rawValue, fireAt: row.fireAt.stored))
        {
            try db.execute(
                sql: """
                    INSERT INTO timer(item_id, kind, fire_at, due_zone, due_source, precision, policy_id, armed_by_event)
                    VALUES (?,?,?,?,?,?,?,?)
                    """,
                arguments: [
                    id, row.kind.rawValue, row.fireAt.stored, row.zone, row.source.rawValue, row.precision.rawValue,
                    row.policy, latestEvent,
                ])
        }
    }

    private static func timerKey(kind: String, fireAt: String) -> String { kind + "|" + fireAt }

    /// Decides every timer whose time has come and that nobody decided for its window: each is fired, or skipped when
    /// it is stale, and only a few fire in one pass (`Timers.decide`). A decision is one `timer_fired` row, unique per
    /// timer and window, so a second pass decides nothing twice. A fire writes nothing on the fact: it never closes
    /// it, and what the app does about it is for the caller to say.
    @discardableResult
    public func fireTimers() throws -> [FiredTimer] {
        let now = clock()
        return try writer.write { db in
            let settings = try Queries.runSettings(in: db)
            let pending = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, item_id, kind, fire_at FROM timer
                    WHERE cancelled_by_event IS NULL AND fire_at <= ? AND NOT EXISTS (
                        SELECT 1 FROM timer_fired WHERE timer_id = timer.id AND window_key = timer.fire_at)
                    """, arguments: [now.stored])
            let byID = Dictionary(uniqueKeysWithValues: try pending.map { ($0["id"] as Int64, try $0.date("fire_at")) })
            let rows = Dictionary(uniqueKeysWithValues: pending.map { ($0["id"] as Int64, $0) })
            return try Timers.decide(byID.map { (id: $0.key, fireAt: $0.value) }, now: now, settings: settings).map {
                decision in
                try db.execute(
                    sql: """
                        INSERT INTO timer_fired(timer_id, window_key, decided_at, outcome)
                        SELECT id, fire_at, ?, ? FROM timer WHERE id = ?
                        """, arguments: [now.stored, decision.outcome.rawValue, decision.id])
                let row = rows[decision.id]!
                return FiredTimer(
                    timer: decision.id, item: row["item_id"], kind: TimerRow.Kind(rawValue: row["kind"])!,
                    fireAt: byID[decision.id]!, outcome: decision.outcome)
            }
        }
    }

    /// Adds a rule that times open facts: those of `task` whose `field` holds `value` are overdue for an answer after
    /// `duration`. It applies to a fact from the next time the lifecycle reconciles that fact.
    @discardableResult
    public func addSLAPolicy(task: String, field: String, value: String, duration: TimeInterval) throws -> Int64 {
        try writer.write { db in
            try db.execute(
                sql: "INSERT INTO sla_policy(task, field, value, duration_s) VALUES (?,?,?,?)",
                arguments: [task, field, value, Int(duration)])
            return db.lastInsertedRowID
        }
    }
}

extension Queries {
    static func slaPolicies(_ db: Database) throws -> [SLAPolicy] {
        try Row.fetchAll(
            db, sql: "SELECT id, task, field, value, duration_s FROM sla_policy WHERE enabled = 1 ORDER BY id"
        )
        .map {
            SLAPolicy(
                id: $0["id"], task: $0["task"], field: $0["field"], value: $0["value"],
                duration: TimeInterval($0["duration_s"] as Int))
        }
    }

    /// The timers of one fact, newest first, with whether each was cancelled and when each was decided.
    public func timers(of item: Int64) throws -> [StoredTimer] {
        try reader.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT timer.id, kind, fire_at, due_zone, due_source, precision, cancelled_by_event,
                        (SELECT outcome FROM timer_fired WHERE timer_id = timer.id) AS outcome
                    FROM timer WHERE item_id = ? ORDER BY timer.id DESC
                    """, arguments: [item]
            ).map {
                StoredTimer(
                    id: $0["id"], kind: TimerRow.Kind(rawValue: $0["kind"])!, fireAt: try $0.date("fire_at"),
                    zone: $0["due_zone"], source: Due.Source(rawValue: $0["due_source"])!,
                    isCancelled: ($0["cancelled_by_event"] as Int64?) != nil,
                    outcome: ($0["outcome"] as String?).flatMap(Timers.Outcome.init(rawValue:)))
            }
        }
    }
}

/// A timer as the store keeps it.
public struct StoredTimer: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var kind: TimerRow.Kind
    public var fireAt: Date
    public var zone: String
    public var source: Due.Source
    public var isCancelled: Bool
    public var outcome: Timers.Outcome?
}
