import Foundation
import GRDB

extension Store {
    /// Stores one reading of a day by one helper. A whole reading replaces the items the founder has not marked; a
    /// reading of only new lines (`replacing: false`) keeps them. A marked item stays, and a new item that repeats it
    /// is not added. Of the new items, the app picks one at random to ask the founder
    /// about, and keeps the chance it had. The grant is asked after the model ran, so consent withdrawn meanwhile
    /// stops the write.
    public func saveReading(
        _ result: HelperReader.Result, of spec: HelperSpec, day: WorkDay, scope: String, grant: CaptureGrant,
        replacing: Bool = true, pick: (Int) -> Int = { Int.random(in: 0..<$0) }
    ) throws {
        try check(grant, kind: spec.source.kind, label: scope.isEmpty ? nil : scope)
        try writer.write { db in
            if replacing {
                try db.execute(
                    sql: """
                        DELETE FROM item WHERE id IN (
                            SELECT id FROM item_mark WHERE task = ? AND day = ? AND scope = ? AND state = 'proposed')
                        """,
                    arguments: [spec.task, day.description, scope])
            }
            let marked = try Queries.items(db, of: spec.task, day: day, scope: scope)
            var added: [Int64] = []
            for item in result.items where !marked.contains(where: { item.repeats($0, citation: spec.citation) }) {
                try db.execute(
                    sql: """
                        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                            quote, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                        """,
                    arguments: [
                        item.task, item.run, day.description, scope, item.source.rawValue, item.citeFirst,
                        item.citeLast, item.start.stored, item.end.stored, try Coding.json(item.fields), item.quote,
                        clock().stored,
                    ])
                added.append(db.lastInsertedRowID)
            }
            if !added.isEmpty {
                try db.execute(
                    sql: "UPDATE item SET asked_with = ? WHERE id = ?",
                    arguments: [1 / Double(added.count), added[pick(added.count)]])
            }
            if let run = result.run {
                for close in result.closes {
                    try addEvent(
                        db, item: close.item, kind: "close", outcome: close.outcome, at: close.at,
                        by: (run: run, line: close.line, quote: close.quote))
                }
                try Self.recordYield(db, of: run, kept: result.items.count, dropped: result.dropped)
            }
        }
    }

    /// The founder closes an open item by hand, or reopens a closed one: a new event, so the model's close and its
    /// reversal both stay on record.
    public func close(item id: Int64, as outcome: String) throws {
        try writer.write { db in try addEvent(db, item: id, kind: "close", outcome: outcome, at: clock(), by: nil) }
    }

    public func reopen(item id: Int64) throws {
        try writer.write { db in try addEvent(db, item: id, kind: "reopen", outcome: nil, at: clock(), by: nil) }
    }

    private func addEvent(
        _ db: Database, item: Int64, kind: String, outcome: String?, at: Date,
        by model: (run: RunID, line: Int64, quote: String)?
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO item_event(item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor)
                VALUES (?,?,?,?,?,?,?,?,?)
                """,
            arguments: [
                item, kind, outcome, model?.line, model?.quote, at.stored, clock().stored, model?.run,
                model == nil ? "person" : "model",
            ])
    }

    /// Marks are history: each one is a new row, and the latest is the item's state. Taking a mark back is a mark. A
    /// mark on an item the app picked is an audit mark, with the chance the item had.
    public func mark(item id: Int64, as mark: Mark) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO mark(item_id, ts, state, origin, asked_with)
                    SELECT id, ?, ?, CASE WHEN asked_with IS NULL THEN 'voluntary' ELSE 'audit' END, COALESCE(asked_with, 1)
                    FROM item WHERE id = ?
                    """, arguments: [clock().stored, mark.rawValue, id])
        }
    }
}

extension Queries {
    private static let itemColumns = """
        id, task, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote, state, run_id, asked_with,
        status_kind, status_outcome, status_quote, status_at
        """
    /// Items with their mark and their latest close or reopen.
    private static let itemRows = "item_mark LEFT JOIN item_status ON item_status.item_id = item_mark.id"

    /// The items of a machine still open: of a value its lifecycle keeps open, not rejected, and not closed since.
    /// The newest `limit`, oldest first.
    public func openItems(of task: String, lifecycle: HelperSpec.Lifecycle, limit: Int = 300) throws -> [Item] {
        let values = Array(repeating: "?", count: lifecycle.open.count).joined(separator: ",")
        let arguments =
            StatementArguments([task, "$.\(lifecycle.field)"]) + StatementArguments(lifecycle.open) + [limit]
        return try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT \(Self.itemColumns) FROM \(Self.itemRows)
                WHERE task = ? AND state <> 'rejected' AND json_extract(fields, ?) IN (\(values))
                    AND (status_kind IS NULL OR status_kind = 'reopen')
                ORDER BY day DESC, start_at DESC, id DESC LIMIT ?
                """, arguments, as: Item.init(row:)
            ).reversed()
        }
    }

    /// A machine's items closed between two times, by the time of the closing line, oldest first.
    public func closedItems(of task: String, from: Date, to: Date) throws -> [Item] {
        try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT \(Self.itemColumns) FROM \(Self.itemRows)
                WHERE task = ? AND status_kind = 'close' AND status_at >= ? AND status_at < ? ORDER BY status_at, id
                """, [task, from.stored, to.stored], as: Item.init(row:))
        }
    }

    /// One helper's items on one day, in time order.
    public func items(of task: String, day: WorkDay, scope: String) throws -> [Item] {
        try reader.read { db in try Self.items(db, of: task, day: day, scope: scope) }
    }

    /// The same read inside a transaction already open on `db`.
    static func items(_ db: Database, of task: String, day: WorkDay, scope: String) throws -> [Item] {
        try db.fetch(
            "item",
            "SELECT \(itemColumns) FROM \(itemRows) WHERE task = ? AND day = ? AND scope = ? ORDER BY start_at, id",
            [task, day.description, scope], as: Item.init(row:))
    }

    /// One machine's items since `day`, oldest first, in every scope.
    public func items(of task: String, since day: WorkDay) throws -> [Item] {
        try reader.read { db in
            try db.fetch(
                "item",
                "SELECT \(Self.itemColumns) FROM \(Self.itemRows) WHERE task = ? AND day >= ? ORDER BY day, start_at, id",
                [task, day.description], as: Item.init(row:))
        }
    }

    /// Every machine's items still waiting for a mark since `day`: the app's random picks first, then the newest days.
    public func waitingItems(since day: WorkDay) throws -> [Item] {
        try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT \(Self.itemColumns) FROM \(Self.itemRows) WHERE state = 'proposed' AND day >= ?
                ORDER BY asked_with IS NULL, day DESC, start_at, id
                """, [day.description], as: Item.init(row:))
        }
    }
}

extension Item {
    init(row: Row) throws {
        self.init(
            id: try row.optionalValue("id"), task: try row.value("task"), day: try row.workDay("day"),
            scope: try row.value("scope"), source: try row.enumeration("source"),
            citeFirst: try row.value("cite_first"),
            citeLast: try row.value("cite_last"), start: try row.date("start_at"), end: try row.date("end_at"),
            fields: try row.json("fields"), quote: try row.value("quote"), state: try row.enumeration("state"),
            run: try row.value("run_id"), askedWith: try row.optionalValue("asked_with"))
        if try row.optionalValue("status_kind") as String? == "close" {
            closed = Closed(
                outcome: try row.value("status_outcome"), quote: try row.optionalValue("status_quote"),
                at: try row.date("status_at"))
        }
    }
}
