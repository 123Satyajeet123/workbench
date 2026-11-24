import Foundation
import GRDB

/// The records that were written before `derivation` existed get their edges here, in batches, with a cursor, so a kill
/// at any point resumes where it stopped (research 86 §7). Each batch is one transaction that writes edges with
/// `INSERT OR IGNORE` and moves the cursor, so a batch that runs twice adds nothing. The job moves the rows of
/// `run_window` into `run_input`, then asks the same functions as the writers (`Provenance`) for the edges of every
/// fact, event, summary, block, page proposal and judge row. Until the complete flag is set, an erase also uses the old
/// joins.
extension Store {
    static let backfillCursorKey = "provenance.backfill.cursor"
    static let backfillCompleteKey = "provenance.backfill.complete"

    private struct Cursor: Codable {
        var stage: String
        var after: String?
    }

    private struct Stage {
        var name: String
        /// A statement that returns up to `?2` keys greater than `?1`, in order, in the column `key`.
        var keys: String
        var derivations: @Sendable (_ key: String, _ db: Database) throws -> [Derivation]
    }

    private static let stages: [Stage] = [
        Stage(
            name: "items", keys: "SELECT id AS key FROM item WHERE id > CAST(?1 AS INTEGER) ORDER BY id LIMIT ?2",
            derivations: { key, db in
                let id = Int64(key) ?? 0
                return try DerivedSources.ofItem(id, in: db) + DerivedSources.ofOpening(of: id, in: db)
            }),
        Stage(
            name: "events",
            keys: """
                SELECT id AS key FROM item_event WHERE id > CAST(?1 AS INTEGER) AND actor = 'model' AND quote <> ''
                ORDER BY id LIMIT ?2
                """,
            derivations: { key, db in try DerivedSources.ofEvent(Int64(key) ?? 0, in: db) }),
        Stage(
            name: "summaries",
            keys: """
                SELECT json_array(day, task, field, scope) AS key FROM summary
                WHERE json_array(day, task, field, scope) > ?1 ORDER BY key LIMIT ?2
                """,
            derivations: { key, db in
                let parts: [String] = try Coding.value([String].self, from: key)
                let run = try Int64.fetchOne(
                    db,
                    sql:
                        "SELECT json_extract(body, '$.run') FROM summary WHERE json_array(day, task, field, scope) = ?",
                    arguments: [key])
                return try DerivedSources.ofSummary(
                    day: parts[0], task: parts[1], field: parts[2], scope: parts[3], run: run, in: db)
            }),
        Stage(
            name: "proposals",
            keys: "SELECT id AS key FROM proposal WHERE id > CAST(?1 AS INTEGER) ORDER BY id LIMIT ?2",
            derivations: { key, db in [try DerivedSources.ofProposal(Int64(key) ?? 0, in: db)] }),
        Stage(
            name: "actions",
            keys: """
                SELECT id AS key FROM action WHERE id > CAST(?1 AS INTEGER) AND json_type(detail, '$.item') IS NOT NULL
                ORDER BY id LIMIT ?2
                """,
            derivations: { key, db in [try DerivedSources.ofAction(Int64(key) ?? 0, in: db)] }),
        Stage(
            name: "workEvents",
            keys: """
                SELECT id AS key FROM work_event WHERE id > CAST(?1 AS INTEGER)
                    AND json_type(body, '$.item.itemID') IS NOT NULL ORDER BY id LIMIT ?2
                """,
            derivations: { key, db in [try DerivedSources.ofWorkEvent(Int64(key) ?? 0, in: db)] }),
        Stage(
            name: "blocks", keys: "SELECT id AS key FROM machine_block WHERE id > ?1 ORDER BY id LIMIT ?2",
            derivations: { key, db in [try DerivedSources.ofBlock(key, in: db)] }),
        Stage(
            name: "pageProposals",
            keys: "SELECT id AS key FROM page_proposal WHERE id > CAST(?1 AS INTEGER) ORDER BY id LIMIT ?2",
            derivations: { key, db in [try DerivedSources.ofPageProposal(Int64(key) ?? 0, in: db)] }),
        Stage(
            name: "claims",
            keys: "SELECT id AS key FROM product_claim WHERE id > CAST(?1 AS INTEGER) ORDER BY id LIMIT ?2",
            derivations: { key, db in try DerivedSources.ofClaim(Int64(key) ?? 0, in: db) }),
        Stage(
            name: "products",
            keys: "SELECT id AS key FROM work_product WHERE id > CAST(?1 AS INTEGER) ORDER BY id LIMIT ?2",
            derivations: { key, db in [try DerivedSources.ofProduct(Int64(key) ?? 0, in: db)] }),
        Stage(
            name: "verdicts",
            keys: "SELECT id AS key FROM judge_verdict WHERE id > CAST(?1 AS INTEGER) ORDER BY id LIMIT ?2",
            derivations: { key, db in [try DerivedSources.ofVerdict(Int64(key) ?? 0, in: db)] }),
        Stage(
            name: "productMarks",
            keys: """
                SELECT id AS key FROM product_mark WHERE id > CAST(?1 AS INTEGER) AND edited_text IS NOT NULL
                ORDER BY id LIMIT ?2
                """,
            derivations: { key, db in [try DerivedSources.ofProductMark(Int64(key) ?? 0, in: db)] }),
    ]

    private static let runWindowStage = "runWindow"

    static func provenanceBackfillIsComplete(in db: Database) throws -> Bool {
        try String.fetchOne(db, sql: "SELECT value FROM state WHERE key = ?", arguments: [backfillCompleteKey]) != nil
    }

    public func provenanceBackfillIsComplete() throws -> Bool {
        try writer.read { db in try Self.provenanceBackfillIsComplete(in: db) }
    }

    /// Runs batches until the job is complete or `budget` seconds have passed. The hourly hook calls it, off the main
    /// actor; a store with nothing to backfill finishes at once.
    public func advanceProvenanceBackfill(budget: TimeInterval, batchSize: Int = 500) throws {
        let start = ContinuousClock.now
        defer { try? checkpointPassively() }
        while try !provenanceBackfillIsComplete() {
            try backfillBatch(size: batchSize)
            if ContinuousClock.now - start > .seconds(budget) { return }
        }
    }

    /// Moves the log into the database file without waiting for a reader, so the log stays small and the next erase does
    /// not pay for a large truncate.
    func checkpointPassively() throws {
        _ = try writer.writeWithoutTransaction { db in try db.checkpoint(.passive) }
    }

    /// One batch in one transaction: the next keys after the cursor, their edges, and the new cursor. The job is complete
    /// when no stage has a key left.
    func backfillBatch(size: Int) throws {
        try writer.write { db in
            guard try !Self.provenanceBackfillIsComplete(in: db) else { return }
            var cursor = try Self.backfillCursor(in: db)
            while true {
                let processed =
                    cursor.stage == Self.runWindowStage
                    ? try Self.moveRunWindow(after: cursor.after, size: size, in: db)
                    : try Self.backfill(stage: cursor.stage, after: cursor.after, size: size, at: clock(), in: db)
                if let last = processed {
                    cursor.after = last
                    try Self.save(cursor, at: clock(), in: db)
                    return
                }
                guard let next = Self.stageName(after: cursor.stage) else {
                    try Self.upsertState(db, key: Self.backfillCompleteKey, value: "1", savedAt: clock())
                    return
                }
                cursor = Cursor(stage: next, after: nil)
            }
        }
    }

    private static func backfillCursor(in db: Database) throws -> Cursor {
        try String.fetchOne(db, sql: "SELECT value FROM state WHERE key = ?", arguments: [backfillCursorKey])
            .map { try Coding.value(Cursor.self, from: $0) } ?? Cursor(stage: runWindowStage, after: nil)
    }

    private static func save(_ cursor: Cursor, at now: Date, in db: Database) throws {
        try upsertState(db, key: backfillCursorKey, value: try Coding.json(cursor), savedAt: now)
    }

    private static func stageName(after name: String) -> String? {
        let names = [runWindowStage] + stages.map(\.name)
        return names.firstIndex(of: name).flatMap { $0 + 1 < names.count ? names[$0 + 1] : nil }
    }

    /// Edges for the next keys of a stage. Returns the last key, or nil when the stage has no key left.
    private static func backfill(stage name: String, after: String?, size: Int, at now: Date, in db: Database) throws
        -> String?
    {
        guard let stage = stages.first(where: { $0.name == name }) else { return nil }
        let keys = try String.fetchAll(db, sql: stage.keys, arguments: [after ?? "", size])
        for key in keys { try derive(try stage.derivations(key, db), at: now, in: db) }
        return keys.last
    }

    /// Moves the next rows of `run_window` into `run_input`, as lines. The cursor is `run_id:ordinal` of the last row.
    private static func moveRunWindow(after: String?, size: Int, in db: Database) throws -> String? {
        let rows = try Row.fetchAll(
            db, sql: "SELECT run_id, ordinal, line_id FROM run_window ORDER BY run_id, ordinal LIMIT ?",
            arguments: [size])
        for row in rows {
            try db.execute(
                sql: "INSERT INTO run_input(run_id, ordinal, kind, ref) VALUES (?,?,'line',?)",
                arguments: [row["run_id"] as Int64, row["ordinal"] as Int64, row["line_id"] as Data])
            try db.execute(
                sql: "DELETE FROM run_window WHERE run_id = ? AND ordinal = ?",
                arguments: [row["run_id"] as Int64, row["ordinal"] as Int64])
        }
        return rows.last.map { "\($0["run_id"] as Int64):\($0["ordinal"] as Int64)" }
    }
}
