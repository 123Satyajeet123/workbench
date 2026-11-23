import Foundation
import GRDB
import Kernel
import Lines
import Synchronization

public enum EvidenceError: Error, Equatable {
    /// The policy no longer allows this read: the person revoked the chat, paused capture, or switched it off.
    case consentWithdrawn
    /// An erasure that names no source, no grant and no age would erase everything.
    case erasureNamesNothing
}

/// What one ingest wrote.
public struct IngestReport: Sendable {
    /// Lines that were new.
    public var inserted = 0
    /// Lines already stored: only their `last_seen` moved.
    public var seenAgain = 0
    /// New tombstone lines (messages deleted for everyone).
    public var tombstones = 0
    /// Text lines erased because their message was revoked.
    public var erasedLines = 0
    /// Items that cite a revoked message: each lost its quote and was flagged.
    public var flaggedItems = 0
    /// Text lines the store refused because their message was already revoked.
    public var refusedAfterRevoke = 0
    /// Rows of each source type seen, by the source's type code.
    public var census: [Int: TypeCensus] = [:]
    /// Rows that should have been lines but could not be named.
    public var unkeyed = 0
    /// Chats that were not read or not written, and why. The other chats were.
    public var failures: [LabelFailure] = []
    /// Chats whose saved cursor could not be read: each was read from the start.
    public var resetCursors: [String] = []

    public init() {}

    mutating func add(_ other: IngestReport) {
        inserted += other.inserted
        seenAgain += other.seenAgain
        tombstones += other.tombstones
        erasedLines += other.erasedLines
        flaggedItems += other.flaggedItems
        refusedAfterRevoke += other.refusedAfterRevoke
        unkeyed += other.unkeyed
        census.merge(other.census) {
            TypeCensus(rows: $0.rows + $1.rows, rowsWithText: $0.rowsWithText + $1.rowsWithText)
        }
    }
}

/// One `ingest` at a time: a read and its write finish before the next read starts, so a revoke that one read stored
/// is never raced by an older read that still holds the text.
actor SerialGate {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        if busy { await withCheckedContinuation { waiting.append($0) } } else { busy = true }
        defer { leave() }
        return try await body()
    }

    private func leave() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }
}

extension Store {
    /// What a person consented to is a kind and a label. The `grant_id` of a line and the key of its cursor name that
    /// pair, not the five-minute `CaptureGrant`.
    static func grantID(kind: SourceKind, label: String) -> String { "\(kind.rawValue):\(label)" }

    static func cursorKey(grantID: String) -> String { "cursor." + grantID }

    /// Present once the old citation ids of a chat were mapped. An erase leaves it.
    static func legacyKey(grantID: String) -> String { "legacy." + grantID }

    /// What the store kept for this chat: its cursor, and whether its old citation ids were mapped. A cursor that
    /// cannot be decoded counts as none, and is flagged.
    public func scanState(kind: SourceKind, label: String) throws -> ScanState {
        let grantID = Self.grantID(kind: kind, label: label)
        var state = ScanState(legacyMapped: try queries.state(forKey: Self.legacyKey(grantID: grantID)) != nil)
        if let saved = try queries.state(forKey: Self.cursorKey(grantID: grantID)) {
            do {
                state.cursor = try Coding.value(ScanCursor.self, from: saved)
            } catch {
                state.cursorWasCorrupt = true
            }
        }
        return state
    }

    /// Reads what is new from a source and writes it: for each chat, its lines and its cursor in one transaction. A
    /// chat that fails is reported and the others go on. Calls run one after another.
    public func ingest(_ source: some EvidenceSource, owner: PersonID, now: Date) async throws -> IngestReport {
        try await ingestGate.run { try await self.ingestOnce(source, owner: owner, now: now) }
    }

    private func ingestOnce(_ source: some EvidenceSource, owner: PersonID, now: Date) async throws -> IngestReport {
        let descriptor = source.descriptor
        let reset = Mutex<[String]>([])
        let read = try await source.observe(
            state: { label in
                let state = try self.scanState(kind: descriptor.consent, label: label)
                if state.cursorWasCorrupt { reset.withLock { $0.append(label) } }
                return state
            }, now: now)
        var report = IngestReport()
        report.failures = read.failures
        report.resetCursors = reset.withLock { $0 }
        for reading in read.readings {
            do {
                report.add(try record(reading, of: descriptor, owner: owner))
            } catch {
                report.failures.append(LabelFailure(label: reading.label, error: error))
            }
        }
        return report
    }

    /// Writes one reading. The grant must be live, and the policy must allow the chat inside the write transaction
    /// itself: a revoke between the read and the write writes nothing, and none can slip in between the check and the
    /// write. The lines, the erasure that a revoke asks for, the cursor (when the source has one) and the note that
    /// old ids were mapped commit together or not at all; then the log is truncated if any text was erased.
    func record(_ reading: SourceReading, of descriptor: SourceDescriptor, owner: PersonID) throws -> IngestReport {
        try check(reading.grant, kind: descriptor.consent, label: reading.label)
        let request = CaptureRequest(kind: descriptor.consent, label: reading.label)
        let source = try descriptor.sourceID(owner: owner)
        let grantID = Self.grantID(kind: descriptor.consent, label: reading.label)
        let stamp = EvidenceStamp(
            source: source, label: Label(source: source).id, grantID: grantID, reading: reading,
            descriptor: descriptor, now: UTCInstant(clock()))
        var report = try writer.write { db in
            guard try Queries.policy(in: db).authorize(request, at: clock()).grant != nil else {
                throw EvidenceError.consentWithdrawn
            }
            var report = IngestReport()
            for item in reading.lines { report.add(try EvidenceStamp.write(item, stamp, in: db)) }
            if report.erasedLines > 0 { try db.execute(sql: EvidenceStamp.optimizeSearch) }
            if let cursor = reading.cursorAfter {
                try Self.saveCursor(cursor, grantID: grantID, in: db, at: clock())
                if reading.mapsLegacyRefs { try Self.noteLegacyMapped(cursor, grantID: grantID, in: db) }
            }
            return report
        }
        report.census = reading.census
        report.unkeyed = reading.unkeyed
        if report.erasedLines > 0 || report.flaggedItems > 0 { try truncateLog() }
        return report
    }

    /// Keeps the cursor that is further on: two reads that finish out of order cannot undo each other.
    private static func saveCursor(_ cursor: ScanCursor, grantID: String, in db: Database, at now: Date) throws {
        let key = cursorKey(grantID: grantID)
        let stored = try String.fetchOne(db, sql: "SELECT value FROM state WHERE key = ?", arguments: [key])
            .flatMap { try? Coding.value(ScanCursor.self, from: $0) }
        try upsertState(db, key: key, value: try Coding.json(cursor.advanced(from: stored)), savedAt: now)
    }

    private static func noteLegacyMapped(_ cursor: ScanCursor, grantID: String, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO state(key, value, saved_at) VALUES (?, ?, ?) ON CONFLICT(key) DO NOTHING
                """, arguments: [legacyKey(grantID: grantID), cursor.storeID, cursor.readAt.stored])
    }

    /// Writes a small setting inside a transaction that is already open.
    static func upsertState(_ db: Database, key: String, value: String, savedAt: Date) throws {
        try db.execute(
            sql:
                "INSERT INTO state(key, value, saved_at) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, saved_at = excluded.saved_at",
            arguments: [key, value, savedAt.stored])
    }
}

/// The text lines that a revoke of one message erases: those of its entity key, and those of the same chat and
/// source message id whatever their author part (a member's jid can change form).
struct Revoke {
    static let erased = "tombstone = 0 AND (entity_key = ? OR (container = ? AND message_ref = ?))"

    var key: Data
    var container: String
    var messageRef: String?

    var arguments: StatementArguments { [key, container, messageRef] }
}

/// What every line of one reading shares, and the statements that write a line.
struct EvidenceStamp {
    let source: Data
    let label: Data
    let grantID: String
    let container: String
    let audience: Data
    let retention: String
    let obtainedBy: String
    let readerVersion: String
    let now: Int64

    init(
        source: SourceID, label: LabelID, grantID: String, reading: SourceReading, descriptor: SourceDescriptor,
        now: UTCInstant
    ) {
        self.source = Data(source.bytes)
        self.label = Data(label.bytes)
        self.grantID = grantID
        container = reading.container
        audience = Data(reading.audience.bytes)
        retention = descriptor.retention.rawValue
        obtainedBy = descriptor.obtainedBy.rawValue
        readerVersion = reading.readerVersion
        self.now = now.milliseconds
    }

    static let optimizeSearch = "INSERT INTO evidence_fts(evidence_fts) VALUES ('optimize')"

    /// Writes one line. A line already stored only has its `last_seen` moved forward. A tombstone is written first, then
    /// the text lines of its message go, and it takes over their old citations and their places in run windows. A text
    /// line of a revoked message is refused by the store.
    static func write(_ item: ObservedLine, _ stamp: EvidenceStamp, in db: Database) throws -> IngestReport {
        var report = IngestReport()
        let line = item.line
        let key = Data(line.entity.bytes)
        let lineID = Data(line.id.bytes)
        var citations = [item.legacy].compactMap { $0 }.map(LegacyCitations.Row.init)
        try db.execute(
            sql: """
                INSERT INTO evidence(line_id, entity_key, quality, source_id, container, event_time, first_seen,
                    last_seen, actor, text, reply_to, coordinate, message_ref, tombstone, label_id, grant_id,
                    audience_digest, retention_class, obtained_by, walk_complete, reader_version, forwarded)
                SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?
                WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE line_id = ?)
                """,
            arguments: [
                lineID, key, item.quality.rawValue, stamp.source, stamp.container, item.eventTime?.milliseconds,
                stamp.now, stamp.now, item.actor, line.text, item.replyTo.map { Data($0.bytes) }, item.coordinate,
                item.messageRef,
                line.isTombstone ? 1 : 0, stamp.label, stamp.grantID, stamp.audience, stamp.retention,
                stamp.obtainedBy, stamp.readerVersion, item.forwarded ? 1 : 0, lineID,
            ])
        if db.changesCount == 1 {
            if line.isTombstone { report.tombstones = 1 } else { report.inserted = 1 }
        } else if try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM evidence WHERE line_id = ?)", arguments: [lineID]) == true
        {
            report.seenAgain = 1
            try db.execute(
                sql: "UPDATE evidence SET last_seen = max(last_seen, ?) WHERE line_id = ?",
                arguments: [stamp.now, lineID])
        } else {
            report.refusedAfterRevoke = 1
        }
        if line.isTombstone {
            let revoke = Revoke(key: key, container: stamp.container, messageRef: item.messageRef)
            citations += try LegacyCitations.refs(erasedBy: revoke, in: db)
            try db.execute(
                sql: """
                    UPDATE run_window SET line_id = ? WHERE line_id IN (SELECT line_id FROM evidence WHERE \(Revoke.erased))
                    """, arguments: StatementArguments([lineID]) + revoke.arguments)
            try db.execute(sql: "DELETE FROM evidence WHERE \(Revoke.erased)", arguments: revoke.arguments)
            report.erasedLines = db.changesCount
        }
        for citation in citations where report.refusedAfterRevoke == 0 {
            try LegacyCitations.map(citation, to: lineID, in: db)
        }
        if line.isTombstone, report.tombstones == 1 || report.erasedLines > 0 {
            report.flaggedItems = try Store.eraseCopies(of: .line(lineID), in: db)
        }
        return report
    }
}
