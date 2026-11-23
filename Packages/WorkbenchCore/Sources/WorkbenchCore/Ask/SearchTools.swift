import Foundation
import GRDB
import Kernel
import Lines

extension Store {
    /// The facts whose words match, best match first, then newest. A fact comes back only when every line it cites
    /// may be read by the reader, and when its words were not erased. Each line a fact cites goes into the window of
    /// the run.
    public func searchFacts(
        _ words: String, _ filter: FactFilter = .init(), limit: Int = 20, in context: ToolContext
    ) throws -> [FoundFact] {
        guard limit > 0, let match = SearchWords.match(words) else { return [] }
        let audience = try ReaderAudience(reader: context.reader)
        return try writer.write { db in
            let found = try Self.admittedFacts(matching: match, filter, limit: limit, audience: audience, in: db)
            let numbers = try Self.trace(found.flatMap(\.cites), in: context.run, db)
            return try found.map { try $0.found(numbers: numbers) }
        }
    }

    /// The lines whose words match, best match first, then newest: the current version of each message that the
    /// reader may read. Each line goes into the window of the run.
    public func searchLines(
        _ words: String, _ filter: LineFilter = .init(), limit: Int = 20, in context: ToolContext
    ) throws -> [FoundLine] {
        guard limit > 0, let match = SearchWords.match(words) else { return [] }
        let audience = try ReaderAudience(reader: context.reader)
        return try writer.write { db in
            let rows = try Row.fetchCursor(
                db, sql: Self.lineSearch, arguments: try Self.lineSearchArguments(match, filter))
            let found = try Self.admitted(from: rows, limit: limit, audience: audience)
            return try Self.found(found, in: context.run, db)
        }
    }

    /// The line, and `around` lines before it and after it in its chat or mail thread, by time: the current version
    /// of each message. Nothing comes back when the reader may not read the line. A neighbour the reader may not
    /// read is skipped, and the next one takes its place.
    public func readLine(_ line: LineID, around: Int = 0, in context: ToolContext) throws -> [FoundLine] {
        let audience = try ReaderAudience(reader: context.reader)
        return try writer.write { db in
            guard
                let center = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT e.id AS number, \(StoredLine.columns), e.entity_key, \(Self.sentAt) AS sent_at
                        FROM evidence e WHERE e.line_id = ? AND e.tombstone = 0
                        """, arguments: [Data(line.bytes)]),
                audience.admits(StoredLine(row: center))
            else { return [] }
            let before = try Self.neighbours(of: center, before: true, count: around, audience: audience, db)
            let after = try Self.neighbours(of: center, before: false, count: around, audience: audience, db)
            return try Self.found(before.reversed() + [StoredLine(row: center)] + after, in: context.run, db)
        }
    }

    private static let sentAt = "COALESCE(e.event_time, e.first_seen)"

    private static func neighbours(
        of center: Row, before: Bool, count: Int, audience: ReaderAudience, _ db: Database
    ) throws -> [StoredLine] {
        guard count > 0 else { return [] }
        let (compare, order) = before ? ("<", "DESC") : (">", "ASC")
        let rows = try Row.fetchCursor(
            db,
            sql: """
                SELECT e.id AS number, \(StoredLine.columns) FROM evidence e
                WHERE e.container = ? AND e.tombstone = 0 AND e.entity_key <> ? AND \(StoredLine.isCurrentVersion)
                    AND (\(sentAt), e.id) \(compare) (?, ?)
                ORDER BY \(sentAt) \(order), e.id \(order)
                """,
            arguments: [center["container"], center["entity_key"], center["sent_at"], center["number"]])
        return try admitted(from: rows, limit: count, audience: audience)
    }

    private static let lineSearch = """
        SELECT e.id AS number, \(StoredLine.columns) FROM evidence_fts JOIN evidence e ON e.id = evidence_fts.rowid
        WHERE evidence_fts MATCH ? AND e.tombstone = 0 AND \(StoredLine.isCurrentVersion)
            AND (? IS NULL OR substr(e.grant_id, 1, instr(e.grant_id, ':') - 1) IN (SELECT value FROM json_each(?)))
            AND (? IS NULL OR e.event_time >= ?) AND (? IS NULL OR e.event_time < ?)
        ORDER BY bm25(evidence_fts), e.event_time DESC, e.id DESC
        """

    private static func lineSearchArguments(_ match: String, _ filter: LineFilter) throws -> StatementArguments {
        let sources = try filter.sources.map { try Coding.json($0.map(\.rawValue).sorted()) }
        let since = filter.since?.millisecondsSince1970
        let until = filter.until?.millisecondsSince1970
        return [match, sources, sources, since, since, until, until]
    }

    private static func admitted(from rows: RowCursor, limit: Int, audience: ReaderAudience) throws -> [StoredLine] {
        var admitted: [StoredLine] = []
        while admitted.count < limit, let row = try rows.next() {
            let line = StoredLine(row: row)
            if audience.admits(line) { admitted.append(line) }
        }
        return admitted
    }

    private static func found(_ lines: [StoredLine], in run: RunID, _ db: Database) throws -> [FoundLine] {
        let numbers = try trace(lines, in: run, db)
        return try lines.map { try FoundLine($0, number: numbers[$0.lineID] ?? 0) }
    }
}

/// The words of a search as an FTS5 query: each word a phrase of its own, so no word is read as query syntax.
enum SearchWords {
    static func match(_ words: String) -> String? {
        let phrases = words.split(whereSeparator: \.isWhitespace).map {
            "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return phrases.isEmpty ? nil : phrases.joined(separator: " ")
    }
}

extension FoundLine {
    init(_ line: StoredLine, number: Int) throws {
        guard let source = SourceKind(rawValue: String(line.grantID.prefix { $0 != ":" })),
            let lineID = LineID(bytes: Array(line.lineID))
        else { throw StoredValueError("grant_id") }
        self.init(
            number: number, lineID: lineID, text: line.text, source: source, who: line.actor, eventTime: line.time)
    }
}
