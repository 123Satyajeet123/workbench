import Foundation
import GRDB

/// A summary as kept: with the fingerprint of the input it was written from, and the consent kinds of that input.
struct StoredSummary: Sendable, Equatable {
    var fingerprint: String
    var kinds: Set<SourceKind>
    var summary: Summary
}

extension Store {
    /// Replaces the summaries of one day, machine and grouping field: the given ones are written, and any other scope
    /// kept earlier is dropped, because the items it was built from are gone.
    func saveSummaries(_ stored: [StoredSummary], day: WorkDay, task: String, field: String) throws {
        try writer.write { db in
            let kept = stored.map(\.summary.scope)
            let marks = databaseQuestionMarks(count: kept.count)
            try db.execute(
                sql: "DELETE FROM summary WHERE day = ? AND task = ? AND field = ? AND scope NOT IN (\(marks))",
                arguments: StatementArguments([day.description, task, field] + kept))
            for entry in stored {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO summary(day, task, field, scope, fingerprint, kinds, body, saved_at)
                        VALUES (?,?,?,?,?,?,?,?)
                        """,
                    arguments: [
                        day.description, task, field, entry.summary.scope, entry.fingerprint,
                        try Coding.json(entry.kinds.map(\.rawValue).sorted()), try Coding.json(entry.summary),
                        clock().stored,
                    ])
            }
        }
    }

    /// Drops the summaries built from a kind of source, up to the day of the cutoff: coarse, and in the safe direction.
    func removeSummaries(_ db: Database, holding kinds: [SourceKind], before cutoff: Date) throws {
        let marks = databaseQuestionMarks(count: kinds.count)
        try db.execute(
            sql: """
                DELETE FROM summary WHERE day <= ? AND EXISTS (
                    SELECT 1 FROM json_each(summary.kinds) WHERE value IN (\(marks)))
                """,
            arguments: StatementArguments([WorkDay(containing: cutoff).description] + kinds.map(\.rawValue)))
    }

    /// Removes the summaries of the day and machine of the items in `itemIDs` (a JSON array of ids) whose scope names a
    /// value of one of those items: coarse, and in the safe direction. Returns the runs that wrote them.
    static func removeSummaries(_ db: Database, builtFromItems itemIDs: String) throws -> [Int64] {
        let built = """
            FROM summary WHERE EXISTS (
                SELECT 1 FROM item WHERE item.id IN (SELECT value FROM json_each(?)) AND item.day = summary.day
                    AND item.task = summary.task AND EXISTS (
                        SELECT 1 FROM json_each(item.fields) AS field WHERE field.key || ': ' || field.value = summary.scope))
            """
        let runs = try Int64.fetchAll(db, sql: "SELECT json_extract(body, '$.run') \(built)", arguments: [itemIDs])
        try db.execute(sql: "DELETE \(built)", arguments: [itemIDs])
        return runs
    }

    func removeSummaries(_ db: Database, tasks: [String]) throws {
        let marks = databaseQuestionMarks(count: tasks.count)
        try db.execute(sql: "DELETE FROM summary WHERE task IN (\(marks))", arguments: StatementArguments(tasks))
    }
}

extension Queries {
    /// The summaries kept for one day, machine and grouping field, in order of name. A page reads these; it never
    /// asks the model.
    public func summaries(day: WorkDay, task: String, field: String) throws -> [Summary] {
        try storedSummaries(day: day, task: task, field: field).values.map(\.summary).sorted { $0.scope < $1.scope }
    }

    func storedSummaries(day: WorkDay, task: String, field: String) throws -> [String: StoredSummary] {
        try reader.read { db in
            let rows = try db.fetch(
                "summary", "SELECT fingerprint, kinds, body FROM summary WHERE day = ? AND task = ? AND field = ?",
                [day.description, task, field]
            ) { row -> StoredSummary in
                let names: [String] = try row.json("kinds")
                return StoredSummary(
                    fingerprint: try row.value("fingerprint"),
                    kinds: Set(
                        try names.map { name in
                            guard let kind = SourceKind(rawValue: name) else { throw StoredValueError("kinds") }
                            return kind
                        }), summary: try row.json("body"))
            }
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.summary.scope, $0) })
        }
    }
}
