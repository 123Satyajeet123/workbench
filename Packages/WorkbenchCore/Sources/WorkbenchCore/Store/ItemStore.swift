import Foundation
import GRDB

extension Store {
    static let toldBeforeDays = 14

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
            let known =
                spec.citation == .facts
                ? try Queries.items(db, of: spec.task, since: day.adding(days: -Self.toldBeforeDays))
                : try Queries.items(db, of: spec.task, day: day, scope: scope)
            var added: [Int64] = []
            for item in result.items
            where !known.contains(where: { item.repeats($0, citation: spec.citation, choices: spec.choiceFields) }) {
                added.append(
                    try Self.insertItem(
                        db, task: item.task, run: item.run, day: day, scope: scope, source: item.source,
                        cite: (item.citeFirst, item.citeLast), span: (item.start, item.end), fields: item.fields,
                        quote: item.quote, at: clock()))
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

    static func insertItem(
        _ db: Database, task: String, run: RunID?, day: WorkDay, scope: String, source: SourceKind,
        cite: (first: Int64, last: Int64), span: (start: Date, end: Date), fields: [String: String], quote: String,
        at now: Date
    ) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                    quote, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            arguments: [
                task, run, day.description, scope, source.rawValue, cite.first, cite.last, span.start.stored,
                span.end.stored, try Coding.json(fields), quote, now.stored,
            ])
        return db.lastInsertedRowID
    }

    public func close(item id: Int64, as outcome: String) throws {
        try writer.write { db in try addEvent(db, item: id, kind: "close", outcome: outcome, at: clock(), by: nil) }
    }

    public func reopen(item id: Int64) throws {
        try writer.write { db in try addEvent(db, item: id, kind: "reopen", outcome: nil, at: clock(), by: nil) }
    }

    func addEvent(
        _ db: Database, item: Int64, kind: String, outcome: String? = nil, until: Date? = nil, at: Date,
        by model: (run: RunID, line: Int64, quote: String)? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO item_event(item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor,
                    until) VALUES (?,?,?,?,?,?,?,?,?,?)
                """,
            arguments: [
                item, kind, outcome, model?.line, model?.quote, at.stored, clock().stored, model?.run,
                model == nil ? "person" : "model", until?.stored,
            ])
    }

    public func mark(item id: Int64, as mark: Mark) throws {
        try writer.write { db in try addMark(db, item: id, mark) }
    }

    func addMark(_ db: Database, item id: Int64, _ mark: Mark) throws {
        try db.execute(
            sql: """
                INSERT INTO mark(item_id, ts, state, origin, asked_with)
                SELECT id, ?, ?, CASE WHEN asked_with IS NULL THEN 'voluntary' ELSE 'audit' END, COALESCE(asked_with, 1)
                FROM item WHERE id = ?
                """, arguments: [clock().stored, mark.rawValue, id])
    }
}

extension Queries {
    static let itemColumns = """
        id, task, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote, state, run_id, asked_with,
        status_kind, status_outcome, status_quote, status_at, hiding_kind, hiding_until
        """
    static let itemRows = """
        item_mark LEFT JOIN item_status ON item_status.item_id = item_mark.id
            LEFT JOIN item_hiding ON item_hiding.item_id = item_mark.id
        """

    public func openItems(
        of task: String, lifecycle: HelperSpec.Lifecycle, asOf day: WorkDay? = nil, limit: Int = 300
    ) throws -> [Item] {
        guard !lifecycle.open.isEmpty else { return [] }
        let values = databaseQuestionMarks(count: lifecycle.open.count)
        let status: String
        var bounds = StatementArguments()
        if let day {
            status = """
                day <= ? AND (SELECT kind FROM item_event WHERE item_id = item_mark.id AND kind IN ('close','reopen')
                    AND valid_at < ? ORDER BY id DESC LIMIT 1) IS NOT 'close'
                """
            bounds = [day.description, day.start.stored]
        } else {
            status = "(status_kind IS NULL OR status_kind = 'reopen')"
        }
        let arguments =
            StatementArguments([task, "$.\(lifecycle.field)"]) + StatementArguments(lifecycle.open) + bounds + [limit]
        return try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT \(Self.itemColumns) FROM \(Self.itemRows)
                WHERE task = ? AND state <> 'rejected' AND json_extract(fields, ?) IN (\(values)) AND \(status)
                ORDER BY day DESC, start_at DESC, id DESC LIMIT ?
                """, arguments, as: Item.init(row:)
            ).reversed()
        }
    }

    public func openItems(readBy spec: HelperSpec, asOf day: WorkDay? = nil) throws -> [Item] {
        if let lifecycle = spec.lifecycle { return try openItems(of: spec.task, lifecycle: lifecycle, asOf: day) }
        guard let follows = spec.follows,
            let lifecycle = try machines().first(where: { $0.task == follows })?.spec.lifecycle
        else { return [] }
        return try openItems(of: follows, lifecycle: lifecycle, asOf: day) + openDealActions(asOf: day)
    }

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

    public func items(of task: String, day: WorkDay, scope: String) throws -> [Item] {
        try reader.read { db in try Self.items(db, of: task, day: day, scope: scope) }
    }

    static func items(_ db: Database, of task: String, day: WorkDay, scope: String) throws -> [Item] {
        try db.fetch(
            "item",
            "SELECT \(itemColumns) FROM \(itemRows) WHERE task = ? AND day = ? AND scope = ? ORDER BY start_at, id",
            [task, day.description, scope], as: Item.init(row:))
    }

    public func items(of task: String, on day: WorkDay) throws -> [Item] {
        try reader.read { db in
            try db.fetch(
                "item",
                "SELECT \(Self.itemColumns) FROM \(Self.itemRows) WHERE task = ? AND day = ? ORDER BY start_at, id",
                [task, day.description], as: Item.init(row:))
        }
    }

    public func items(of task: String, since day: WorkDay) throws -> [Item] {
        try reader.read { db in try Self.items(db, of: task, since: day) }
    }

    static func items(_ db: Database, of task: String, since day: WorkDay) throws -> [Item] {
        try db.fetch(
            "item",
            "SELECT \(itemColumns) FROM \(itemRows) WHERE task = ? AND day >= ? ORDER BY day, start_at, id",
            [task, day.description], as: Item.init(row:))
    }

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
            run: try row.optionalValue("run_id"), askedWith: try row.optionalValue("asked_with"))
        if try row.optionalValue("status_kind") as String? == "close" {
            closed = Closed(
                outcome: try row.value("status_outcome"), quote: try row.optionalValue("status_quote"),
                at: try row.date("status_at"))
        }
        hiding = try Self.hiding(row)
    }

    private static func hiding(_ row: Row) throws -> Hiding? {
        switch try row.optionalValue("hiding_kind") as String? {
        case "hide": .hidden
        case "snooze": .snoozed(until: try row.date("hiding_until"))
        default: nil
        }
    }
}
