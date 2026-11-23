import Foundation
import GRDB
import Lines

/// The lines whose words must leave every copy: a statement that selects `line_id` values, with its arguments.
struct LineSelection {
    var sql: String
    var arguments: StatementArguments

    static func line(_ lineID: Data) -> LineSelection {
        LineSelection(sql: "SELECT line_id FROM evidence WHERE line_id = ?", arguments: [lineID])
    }
}

/// A row that cites a line through a run window or an old citation id, found for the one erase of copies.
private struct Citing: FetchableRecord {
    var id: Int64
    var scope: String
    var container: String

    init(row: Row) {
        id = row["id"]
        scope = row["scope"]
        container = row["container"]
    }

    /// A fact of one chat cites only lines of that chat: old row numbers are global, so a range holds other chats.
    var isInItsOwnChat: Bool { scope.isEmpty || WhatsAppJID.canonical(scope) == container }
}

extension Store {
    /// The one erase of copies. The model read the words of a line and kept them in the quote of each item that cites
    /// it, in the words of the blocks it put on a page that cite the line or such an item, in the text fields it wrote
    /// for that item, in the quotes of the events that cite the line and the quote its open event kept, in the text of the runs
    /// that read it or made those items, and in the summaries built from those items. They all go with the line: the
    /// quote and every text field of the item are emptied and the item flagged (it keeps its marks, its choices and its
    /// link to the tombstone), the quotes of its events are emptied, the run text is deleted (the run row stays as the
    /// meter), and the summaries are removed, so the next reading builds them again without the item. Run it before the lines are deleted, because deleting a line
    /// deletes the rows that link it to its copies, or after a revoke moved those rows to the tombstone. Returns how
    /// many items were flagged.
    @discardableResult
    static func eraseCopies(of lines: LineSelection, in db: Database) throws -> Int {
        let items = try citingItems(of: lines, in: db)
        let events = try citingEvents(of: lines, in: db)
        let itemIDs = try Coding.json(items.map(\.id))
        try eraseMachineWords(citing: lines, orFacts: itemIDs, in: db)
        let eventIDs = try Coding.json(events.map(\.id))
        let windowRuns = try Int64.fetchAll(
            db, sql: "SELECT run_id FROM run_window WHERE line_id IN (\(lines.sql))", arguments: lines.arguments)
        let itemRuns = try Int64.fetchAll(
            db, sql: "SELECT run_id FROM item WHERE run_id IS NOT NULL AND id IN (SELECT value FROM json_each(?))",
            arguments: [itemIDs])
        let eventRuns = try Int64.fetchAll(
            db, sql: "SELECT run_id FROM item_event WHERE id IN (SELECT value FROM json_each(?))",
            arguments: [eventIDs])
        let summaryRuns = try removeSummaries(db, builtFromItems: itemIDs)
        try db.execute(
            sql: "UPDATE item SET quote = '', source_deleted = 1 WHERE id IN (SELECT value FROM json_each(?))",
            arguments: [itemIDs])
        try emptyModelWords(ofItems: itemIDs, in: db)
        try db.execute(
            sql: """
                UPDATE item_event SET quote = '' WHERE actor = 'model' AND (
                    id IN (SELECT value FROM json_each(?))
                    OR (kind = 'open' AND item_id IN (SELECT value FROM json_each(?))))
                """, arguments: [eventIDs, itemIDs])
        try db.execute(
            sql: "DELETE FROM run_text WHERE run_id IN (SELECT value FROM json_each(?))",
            arguments: [try Coding.json(Set(windowRuns + itemRuns + eventRuns + summaryRuns).sorted())])
        return items.count
    }

    /// Empties every field of the items that holds words the model wrote: all but the choices, member names, dates and
    /// computed values of the machine's spec, and the ids of the facts a finding cites. A machine that is not found
    /// keeps only the ids, so no words survive.
    private static func emptyModelWords(ofItems itemIDs: String, in db: Database) throws {
        let rows = try Row.fetchAll(
            db, sql: "SELECT id, task, fields FROM item WHERE id IN (SELECT value FROM json_each(?))",
            arguments: [itemIDs])
        for row in rows {
            let spec = try machineSpec(ofTask: Trial.machineTask(of: row["task"]), in: db)
            let kept = spec?.fieldsWithoutWords ?? [Item.factsField]
            let fields: [String: String] = try row.json("fields")
            let emptied = fields.mapValues { _ in "" }.merging(fields.filter { kept.contains($0.key) }) { _, held in
                held
            }
            try db.execute(
                sql: "UPDATE item SET fields = ? WHERE id = ?",
                arguments: [try Coding.json(emptied), row["id"] as Int64])
        }
    }

    static func machineSpec(ofTask task: String, in db: Database) throws -> HelperSpec? {
        try String.fetchOne(db, sql: "SELECT spec FROM machine_now WHERE task = ?", arguments: [task])
            .map { try Coding.value(HelperSpec.self, from: $0) }
    }

    /// Items that cite one of the lines: by their cited numbers in the window of their run; for an item with no run, by
    /// the line its quote is in, numbered by its evidence row; or, for an item made before runs kept their windows, by
    /// the old citation ids of its chat.
    private static func citingItems(of lines: LineSelection, in db: Database) throws -> [Citing] {
        let byWindow = try Citing.fetchAll(
            db,
            sql: """
                SELECT item.id, item.scope, '' AS container FROM item
                JOIN run_window w ON w.run_id = item.run_id AND w.ordinal BETWEEN item.cite_first AND item.cite_last
                WHERE item.source_deleted = 0 AND w.line_id IN (\(lines.sql))
                """, arguments: lines.arguments)
        let byQuote = try Citing.fetchAll(
            db,
            sql: """
                SELECT item.id, item.scope, '' AS container FROM item JOIN evidence e ON e.id = item.quote_line
                WHERE item.source_deleted = 0 AND item.run_id IS NULL AND e.line_id IN (\(lines.sql))
                """, arguments: lines.arguments)
        let byOldID = try LegacySpace.byKind.flatMap { kind, space in
            try Citing.fetchAll(
                db,
                sql: """
                    SELECT item.id, item.scope, e.container FROM item
                    JOIN evidence_legacy l ON l.space = ? AND l.ref BETWEEN item.cite_first AND item.cite_last
                    JOIN evidence e ON e.line_id = l.line_id
                    WHERE item.source_deleted = 0 AND item.source = ? AND l.line_id IN (\(lines.sql))
                        AND NOT EXISTS (SELECT 1 FROM run_window WHERE run_id = item.run_id)
                    """,
                arguments: StatementArguments([space.rawValue, kind.rawValue]) + lines.arguments)
        }
        return Self.distinct(byWindow + byQuote + byOldID.filter(\.isInItsOwnChat))
    }

    /// Closes the model wrote with the closing words of one of the lines, found the same two ways.
    private static func citingEvents(of lines: LineSelection, in db: Database) throws -> [Citing] {
        let byWindow = try Citing.fetchAll(
            db,
            sql: """
                SELECT ev.id, '' AS scope, '' AS container FROM item_event ev
                JOIN run_window w ON w.run_id = ev.run_id AND w.ordinal = ev.line_id
                WHERE ev.actor = 'model' AND ev.quote <> '' AND w.line_id IN (\(lines.sql))
                """, arguments: lines.arguments)
        let byOldID = try LegacySpace.byKind.flatMap { kind, space in
            try Citing.fetchAll(
                db,
                sql: """
                    SELECT ev.id, item.scope, e.container FROM item_event ev JOIN item ON item.id = ev.item_id
                    JOIN evidence_legacy l ON l.space = ? AND l.ref = ev.line_id
                    JOIN evidence e ON e.line_id = l.line_id
                    WHERE ev.actor = 'model' AND ev.quote <> '' AND item.source = ? AND l.line_id IN (\(lines.sql))
                        AND NOT EXISTS (SELECT 1 FROM run_window WHERE run_id = ev.run_id)
                    """,
                arguments: StatementArguments([space.rawValue, kind.rawValue]) + lines.arguments)
        }
        return Self.distinct(byWindow + byOldID.filter(\.isInItsOwnChat))
    }

    private static func distinct(_ found: [Citing]) -> [Citing] {
        var seen: Set<Int64> = []
        return found.filter { seen.insert($0.id).inserted }
    }
}
