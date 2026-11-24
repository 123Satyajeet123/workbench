import Foundation
import GRDB

/// The events one part of a reading adds to its journal. `Store.saveReading` writes them in the same transaction as the
/// part, so the journal always folds to the parts that are saved. `reading` is the first model call of the reading.
public struct PartJournal: Sendable, Equatable {
    public var reading: RunID
    public var events: [RunEvent]

    public init(reading: RunID, events: [RunEvent]) {
        self.reading = reading
        self.events = events
    }
}

/// A journal as the store keeps it, with the time of its first event and, when it finished, of its last.
public struct StoredJournal: Sendable, Equatable {
    public var reading: RunID
    public var events: [RunEvent]
    public var began: Date
    public var ended: Date?

    public var state: RunState {
        get throws { try RunState.fold(events) }
    }
}

extension Store {
    static func append(_ db: Database, _ events: [RunEvent], to reading: RunID, at now: Date) throws {
        var seq =
            try Int.fetchOne(
                db, sql: "SELECT COALESCE(MAX(seq), 0) FROM run_event WHERE run_id = ?", arguments: [reading]) ?? 0
        for event in events {
            seq += 1
            let row = try RunEventRow(event)
            try db.execute(
                sql: """
                    INSERT INTO run_event(run_id, seq, at, kind, lines, parts, part, part_run, count, tag, by_rule, cost)
                    VALUES (\(databaseQuestionMarks(count: 12)))
                    """,
                arguments: [
                    reading, seq, now.stored, row.kind, row.lines, row.parts, row.part, row.partRun, row.count, row.tag,
                    row.byRule, row.cost,
                ])
        }
    }

    /// Ends the journal of a reading that stopped: how it stopped and what its calls cost. A reading whose first part
    /// never saved has no journal yet, so `opening` goes first. A reading that made no model call has none, and a
    /// journal that finished is left as it is. `reading` is its first call when known, else the first call of `task`
    /// after the run `watermark`.
    func endJournal(
        of task: String, reading: RunID?, after watermark: RunID, opening: RunEvent, stop: RunState.Stop
    ) throws {
        try writer.write { db in
            guard let reading = try reading ?? Self.firstRun(db, of: task, after: watermark),
                !(try Self.isFinished(db, reading))
            else { return }
            let opened = try Self.hasEvents(db, reading)
            let runs = try Self.runs(db, of: task, from: reading)
            try Self.append(
                db, (opened ? [] : [opening]) + RunEvent.ending(runs: runs, stop: stop), to: reading, at: clock())
        }
    }

    /// A journal still open when the app starts was cut off: it ends as a failure of kind `other`, with the cost of
    /// the calls from its first call up to the first call of the next reading of the same task.
    static func endInterruptedJournals(_ db: Database, at now: Date) throws {
        let open = try Row.fetchAll(
            db,
            sql: """
                SELECT DISTINCT journal.run_id AS reading, run.task FROM run_event journal JOIN run ON run.id = journal.run_id
                WHERE NOT EXISTS (SELECT 1 FROM run_event WHERE run_id = journal.run_id AND kind = 'finished')
                """)
        for row in open {
            let reading: RunID = row["reading"]
            let task: String = row["task"]
            let next = try RunID.fetchOne(
                db,
                sql: """
                    SELECT MIN(journal.run_id) FROM run_event journal JOIN run ON run.id = journal.run_id
                    WHERE run.task = ? AND journal.run_id > ?
                    """, arguments: [task, reading])
            let runs = try Self.runs(db, of: task, from: reading, before: next)
            try append(db, RunEvent.ending(runs: runs, stop: .failed(.other)), to: reading, at: now)
        }
    }

    private static func isFinished(_ db: Database, _ reading: RunID) throws -> Bool {
        try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM run_event WHERE run_id = ? AND kind = 'finished')",
            arguments: [reading]) ?? false
    }

    private static func hasEvents(_ db: Database, _ reading: RunID) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM run_event WHERE run_id = ?)", arguments: [reading])
            ?? false
    }

    private static func firstRun(_ db: Database, of task: String, after watermark: RunID) throws -> RunID? {
        try RunID.fetchOne(
            db, sql: "SELECT MIN(id) FROM run WHERE task = ? AND id > ?", arguments: [task, watermark])
    }

    /// The model calls of one reading: those of `task` from its first call up to, but not including, `next`.
    static func runs(_ db: Database, of task: String, from first: RunID, before next: RunID? = nil) throws -> [Run] {
        try db.fetch(
            "run", "SELECT \(Run.columns) FROM run WHERE task = ? AND id >= ? AND id < ? ORDER BY id",
            [task, first, next ?? Int64.max], as: Run.init(row:))
    }
}

extension Queries {
    /// The id of the last model call of `task`: the mark a reading starts after. 0 when it made none.
    public func latestRun(of task: String) throws -> RunID {
        try reader.read { db in
            try RunID.fetchOne(db, sql: "SELECT COALESCE(MAX(id), 0) FROM run WHERE task = ?", arguments: [task]) ?? 0
        }
    }

    /// The model calls of the reading that began with `first`, as the journal counts them. Read in the same
    /// snapshot as the caller's other reads.
    func runs(of task: String, from first: RunID) throws -> [Run] {
        try reader.read { db in try Store.runs(db, of: task, from: first) }
    }

    /// The journal of the reading whose first call is `reading`; nil when it has none.
    public func journal(of reading: RunID) throws -> StoredJournal? {
        try reader.read { db in try Self.journal(db, of: reading) }
    }

    static func journal(_ db: Database, of reading: RunID) throws -> StoredJournal? {
        let rows = try Row.fetchAll(
            db,
            sql:
                "SELECT at, kind, lines, parts, part, part_run, count, tag, by_rule, cost FROM run_event WHERE run_id = ? ORDER BY seq",
            arguments: [reading])
        guard let first = rows.first else { return nil }
        let events = try rows.map { try RunEventRow(row: $0).event() }
        let ended = try rows.last.flatMap { row -> Date? in
            guard (row["kind"] as String) == "finished" else { return nil }
            return try row.date("at")
        }
        return StoredJournal(reading: reading, events: events, began: try first.date("at"), ended: ended)
    }

    /// The reading of `task` with the latest first call that has a journal; nil when none has.
    func latestJournal(of task: String) throws -> StoredJournal? {
        try reader.read { db in
            guard
                let reading = try RunID.fetchOne(
                    db,
                    sql: """
                        SELECT MAX(journal.run_id) FROM run_event journal JOIN run ON run.id = journal.run_id
                        WHERE run.task = ?
                        """, arguments: [task])
            else { return nil }
            return try Self.journal(db, of: reading)
        }
    }

    /// The journal with the latest first call of `task` that finished with no failure and no cancel; nil when none did.
    func latestCleanJournal(of task: String) throws -> StoredJournal? {
        try reader.read { db in
            guard
                let reading = try RunID.fetchOne(
                    db,
                    sql: """
                        SELECT MAX(journal.run_id) FROM run_event journal JOIN run ON run.id = journal.run_id
                        WHERE run.task = ? AND journal.kind = 'finished' AND NOT EXISTS (
                            SELECT 1 FROM run_event stop WHERE stop.run_id = journal.run_id
                                AND stop.kind IN ('failed', 'cancelled'))
                        """, arguments: [task])
            else { return nil }
            return try Self.journal(db, of: reading)
        }
    }

    /// When `task` last made a model call; nil when it never did.
    func lastCall(of task: String) throws -> Date? {
        try reader.read { db in
            try (try String.fetchOne(db, sql: "SELECT MAX(started_at) FROM run WHERE task = ?", arguments: [task]))
                .map { try Date($0, strategy: .iso8601) }
        }
    }
}
