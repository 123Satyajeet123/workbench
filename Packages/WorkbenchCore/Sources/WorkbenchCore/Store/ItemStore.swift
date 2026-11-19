import Foundation

extension Store {
    /// Stores one reading of a day by one helper. Items the founder has not marked are replaced; a marked item stays,
    /// and a new item that repeats it is not added. Of the new items, the app picks one at random to ask the founder
    /// about, and keeps the chance it had. The grant is asked after the model ran, so consent withdrawn meanwhile
    /// stops the write.
    public func saveReading(
        _ result: HelperReader.Result, of spec: HelperSpec, day: WorkDay, scope: String, grant: CaptureGrant,
        pick: (Int) -> Int = { Int.random(in: 0..<$0) }
    ) throws {
        try check(grant, kind: spec.source.kind, label: scope.isEmpty ? nil : scope)
        try database.transaction {
            try database.run(
                """
                DELETE FROM item WHERE id IN (
                    SELECT id FROM item_mark WHERE task = ? AND day = ? AND scope = ? AND state = 'proposed')
                """,
                [.text(spec.task), .text(day.description), .text(scope)])
            let marked = try queries.items(of: spec.task, day: day, scope: scope)
            var added: [Int64] = []
            for item in result.items where !marked.contains(where: { item.repeats($0, citation: spec.citation) }) {
                added.append(
                    try database.run(
                        """
                        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                            quote, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                        """,
                        [
                            .text(item.task), .int(item.run), .text(day.description), .text(scope),
                            .text(item.source.rawValue), .int(item.citeFirst), .int(item.citeLast),
                            SQLValue(item.start),
                            SQLValue(item.end), .text(try Coding.json(item.fields)), .text(item.quote),
                            SQLValue(clock()),
                        ]))
            }
            if !added.isEmpty {
                try database.run(
                    "UPDATE item SET asked_with = ? WHERE id = ?",
                    [.real(1 / Double(added.count)), .int(added[pick(added.count)])])
            }
            if let run = result.run { try recordYield(of: run, kept: result.items.count, dropped: result.dropped) }
        }
    }

    /// Marks are history: each one is a new row, and the latest is the item's state. Taking a mark back is a mark. A
    /// mark on an item the app picked is an audit mark, with the chance the item had.
    public func mark(item id: Int64, as mark: Mark) throws {
        try database.run(
            """
            INSERT INTO mark(item_id, ts, state, origin, asked_with)
            SELECT id, ?, ?, CASE WHEN asked_with IS NULL THEN 'voluntary' ELSE 'audit' END, COALESCE(asked_with, 1)
            FROM item WHERE id = ?
            """, [SQLValue(clock()), .text(mark.rawValue), .int(id)])
    }
}

extension Queries {
    /// One helper's items on one day, in time order.
    public func items(of task: String, day: WorkDay, scope: String) throws -> [Item] {
        try database.rows(
            """
            SELECT id, source, cite_first, cite_last, start_at, end_at, fields, quote, state, run_id, asked_with
            FROM item_mark
            WHERE task = ? AND day = ? AND scope = ? ORDER BY start_at, id
            """, [.text(task), .text(day.description), .text(scope)]
        ).compactMap { row in
            guard let source = row[1].string.flatMap(SourceKind.init), let start = row[4].date, let end = row[5].date,
                let state = row[8].string.flatMap(Mark.init),
                let fields = try? Coding.value([String: String].self, from: row[6].string ?? "")
            else { return nil }
            return Item(
                id: row[0].integer, task: task, day: day, scope: scope, source: source, citeFirst: row[2].integer ?? 0,
                citeLast: row[3].integer ?? 0, start: start, end: end, fields: fields, quote: row[7].string ?? "",
                state: state, run: row[9].integer ?? 0, askedWith: row[10].double)
        }
    }
}
