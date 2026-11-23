import Foundation
import GRDB

extension Schema {
    /// Timers of open facts (research 59 §1 Timers row, M2 step 4). A timer is one time at which something should
    /// happen to one fact: `kind` `due` is the fact's due time, `sla` is a policy's time from its opening. It is
    /// derived by the lifecycle (`Store.reconcileTimers`) and never deleted: a fact that ends cancels its timers, by the
    /// event that ended it, and a new due time cancels the old timer by its event and arms another. `fire_at` is
    /// UTC and `due_zone` the owner's zone at the line. A timer for a fact with no due time does not exist, so no
    /// `none` source is stored. `timer_fired` holds one decision per timer and window, so a window is decided once;
    /// a fire writes nothing on the fact. `sla_policy` is data: the facts of a machine whose `field` holds `value`.
    ///
    /// `moveLegacyDueDays` runs with this step and moves the old free-text `eta` days into the field `due`.
    static let timers = [
        """
        CREATE TABLE sla_policy(
            id INTEGER PRIMARY KEY, task TEXT NOT NULL CHECK(task <> ''), field TEXT NOT NULL CHECK(field <> ''),
            value TEXT NOT NULL CHECK(value <> ''), duration_s INTEGER NOT NULL CHECK(duration_s > 0),
            enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)))
        """,
        """
        CREATE TABLE timer(
            id INTEGER PRIMARY KEY, item_id INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK(kind IN ('due','sla')), fire_at TEXT NOT NULL, due_zone TEXT NOT NULL,
            due_source TEXT NOT NULL CHECK(due_source IN ('stated','resolved','default')),
            precision TEXT NOT NULL CHECK(precision IN ('day','part_of_day','week','none')),
            policy_id INTEGER REFERENCES sla_policy(id), armed_by_event INTEGER NOT NULL REFERENCES item_event(id),
            cancelled_by_event INTEGER REFERENCES item_event(id), UNIQUE(item_id, kind, fire_at))
        """,
        """
        CREATE TABLE timer_fired(
            id INTEGER PRIMARY KEY, timer_id INTEGER NOT NULL REFERENCES timer(id) ON DELETE CASCADE,
            window_key TEXT NOT NULL, decided_at TEXT NOT NULL, outcome TEXT NOT NULL CHECK(outcome IN ('fired','skip_stale')),
            UNIQUE(timer_id, window_key))
        """,
    ]

    /// Runs with the step, in its transaction: moves a due day from the old free-text `eta` field into the field `due`
    /// for the facts that hold a day written yyyy-MM-dd there, and arms a timer for each of them that is still open.
    /// The old text is kept. The zone the day was meant in is not stored, so the migration takes the owner's zone
    /// (this Mac's, at the time of the migration) and marks it as assumed.
    static func moveLegacyDueDays(_ db: Database, zone: TimeZone) throws {
        let calendar = Calendar.gregorian(in: zone)
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT item.id, item.fields, (item_status.status_kind IS NULL OR item_status.status_kind = 'reopen') AS isOpen,
                    (SELECT MIN(id) FROM item_event WHERE item_id = item.id AND kind = 'open') AS opened
                FROM item LEFT JOIN item_status ON item_status.item_id = item.id
                WHERE json_extract(item.fields, '$.eta') GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                """)
        for row in rows {
            var fields: [String: String] = try row.json("fields")
            let parts = (fields["eta"] ?? "").split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                calendar.dateComponents([.month, .day], from: day).month == parts[1],
                let end = calendar.endOfDay(of: day)
            else { continue }
            var due = Due(utc: end, zone: zone.identifier, source: .stated, precision: .day)
            due.zoneAssumed = true
            fields[Item.dueField] = try Coding.json(due)
            try db.execute(
                sql: "UPDATE item SET fields = ? WHERE id = ?",
                arguments: [try Coding.json(fields), row["id"] as Int64])
            guard row["isOpen"] as Bool else { continue }
            try db.execute(
                sql: """
                    INSERT INTO timer(item_id, kind, fire_at, due_zone, due_source, precision, armed_by_event)
                    VALUES (?, 'due', ?, ?, 'stated', 'day', ?)
                    """, arguments: [row["id"] as Int64, end.stored, zone.identifier, row["opened"] as Int64])
        }
    }
}
