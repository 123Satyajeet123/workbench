import Foundation
import GRDB

struct StoredSummary: Sendable, Equatable {
    var fingerprint: String
    var kinds: Set<SourceKind>
    var summary: Summary
}

extension Store {
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

    func removeSummaries(_ db: Database, holding kinds: [SourceKind], before cutoff: Date) throws {
        let marks = databaseQuestionMarks(count: kinds.count)
        try db.execute(
            sql: """
                DELETE FROM summary WHERE day <= ? AND EXISTS (
                    SELECT 1 FROM json_each(summary.kinds) WHERE value IN (\(marks)))
                """,
            arguments: StatementArguments([WorkDay(containing: cutoff).description] + kinds.map(\.rawValue)))
    }

    func removeSummaries(_ db: Database, tasks: [String]) throws {
        let marks = databaseQuestionMarks(count: tasks.count)
        try db.execute(sql: "DELETE FROM summary WHERE task IN (\(marks))", arguments: StatementArguments(tasks))
    }
}

extension Queries {
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
