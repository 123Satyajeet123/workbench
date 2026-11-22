import Foundation
import GRDB
import Lines

/// A stored evidence line as the app reads it. The model's input and a proof card both show it, so what the model saw
/// and what the person is shown come from the same rows.
public struct StoredLine: Sendable, Equatable {
    /// The number in front of the line in a run's input: the row number of its evidence row, or the number a run
    /// recorded in its window, or the old citation id.
    public var number: Int64
    public var lineID: Data
    public var container: String
    public var time: Date?
    /// The jid of the sender, or `me`.
    public var actor: String?
    /// The words. Empty for a tombstone.
    public var text: String
    /// The message was deleted for everyone: the line keeps its time and sender, and no words.
    public var isTombstone: Bool

    public init(
        number: Int64, lineID: Data, container: String, time: Date?, actor: String?, text: String, isTombstone: Bool
    ) {
        self.number = number
        self.lineID = lineID
        self.container = container
        self.time = time
        self.actor = actor
        self.text = text
        self.isTombstone = isTombstone
    }

    init(row: Row) {
        let milliseconds: Int64? = row["event_time"]
        self.init(
            number: row["number"], lineID: row["line_id"], container: row["container"],
            time: milliseconds.map { Date(timeIntervalSince1970: Double($0) / 1000) }, actor: row["actor"],
            text: row["text"], isTombstone: row["tombstone"] == 1)
    }

    static let columns = "e.line_id, e.container, e.event_time, e.actor, e.text, e.tombstone"

    static func fetchAll(_ db: Database, sql: String, arguments: StatementArguments) throws -> [StoredLine] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).map(StoredLine.init(row:))
    }
}

/// One line of a proof card: the cited lines, and the lines around them.
public struct ProofLine: Sendable, Equatable {
    public var line: StoredLine
    public var isCited: Bool
}

extension Queries {
    /// The lines of `containers` whose message was sent in `start..<end`, oldest first: the current version of each
    /// message, and a tombstone for each message deleted for everyone. The current version is the one seen last.
    public func currentLines(in containers: [String], from start: Date, to end: Date) throws -> [StoredLine] {
        guard !containers.isEmpty else { return [] }
        let marks = Array(repeating: "?", count: containers.count).joined(separator: ",")
        return try reader.read { db in
            try StoredLine.fetchAll(
                db,
                sql: """
                    SELECT e.id AS number, \(StoredLine.columns) FROM evidence e
                    WHERE e.container IN (\(marks)) AND e.event_time >= ? AND e.event_time < ?
                        AND e.id = (SELECT v.id FROM evidence v WHERE v.entity_key = e.entity_key
                            ORDER BY v.last_seen DESC, v.id DESC LIMIT 1)
                    ORDER BY e.event_time, e.id
                    """,
                arguments: StatementArguments(containers) + [start.millisecondsSince1970, end.millisecondsSince1970]
            )
        }
    }

    /// Which of the lines numbered `numbers` a reading of `task` read: the numbers of the lines that the window of one of
    /// its runs holds, when `saveReading` saved that run's yield (`run.kept` is set in the same transaction as its
    /// items). A run that failed, or whose save failed, read nothing. A trial runs under its own task, so it reads
    /// nothing for the live machine. A run does not name a scope or a day, and need not: the lines asked about are
    /// already one scope's lines of one day.
    public func numbersRead(by task: String, among numbers: [Int64]) throws -> Set<Int64> {
        guard !numbers.isEmpty else { return [] }
        return try reader.read { db in
            try Set(
                Int64.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT e.id FROM evidence e
                        JOIN run_window w ON w.line_id = e.line_id JOIN run r ON r.id = w.run_id
                        WHERE r.task = ? AND r.kept IS NOT NULL AND e.id IN (SELECT value FROM json_each(?))
                        """, arguments: [task, try Coding.json(numbers)]))
        }
    }

    /// The lines a run's input showed, in time order, each under the number the model read in front of it.
    public func window(of run: RunID) throws -> [StoredLine] {
        try reader.read { db in try Self.window(of: run, in: db) }
    }

    /// The lines that prove an item: the ones it cites and `reach` lines around them, as the run that made the item saw
    /// them. An item made before runs kept their windows resolves through the old citation ids (`evidence_legacy`).
    /// A line whose message was deleted for everyone is a tombstone. Empty when no stored line answers.
    public func proofLines(of item: Item, reach: Int = 2) throws -> [ProofLine] {
        guard item.citeFirst > 0 else { return [] }
        let cited = item.citeFirst...max(item.citeFirst, item.citeLast)
        return try reader.read { db in
            if let run = item.run {
                let window = try Self.window(of: run, in: db)
                if !window.isEmpty { return Self.around(window, cited: cited, reach: reach) }
            }
            guard item.source == .whatsapp else { return [] }
            let refs = (cited.lowerBound - Int64(reach))...(cited.upperBound + Int64(reach))
            return try LegacyCitations.lines(
                in: .whatsAppRow, refs: refs, container: item.scope.isEmpty ? nil : WhatsAppJID.canonical(item.scope),
                db: db
            ).map { ProofLine(line: $0, isCited: cited.contains($0.number)) }
        }
    }

    private static func window(of run: RunID, in db: Database) throws -> [StoredLine] {
        try StoredLine.fetchAll(
            db,
            sql: """
                SELECT w.ordinal AS number, \(StoredLine.columns) FROM run_window w
                JOIN evidence e ON e.line_id = w.line_id WHERE w.run_id = ? ORDER BY e.event_time, w.ordinal
                """, arguments: [run]
        )
    }

    /// The cited lines, and `reach` lines before and after each, in the order given.
    static func around(_ lines: [StoredLine], cited: ClosedRange<Int64>, reach: Int) -> [ProofLine] {
        let hits = lines.indices.filter { cited.contains(lines[$0].number) }
        return lines.indices.filter { index in hits.contains { abs($0 - index) <= reach } }
            .map { ProofLine(line: lines[$0], isCited: cited.contains(lines[$0].number)) }
    }
}

extension Date {
    fileprivate var millisecondsSince1970: Int64 { UTCInstant(self).milliseconds }
}
