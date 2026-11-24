import Foundation
import GRDB
import Kernel
import Lines

/// Which evidence lines to erase. Every field that is set must match: a source, a grant, a grant prefix and an age
/// together mean "this source's lines under this grant that were last seen before the cutoff".
public struct EvidenceErasure: Sendable, Equatable {
    public var source: SourceID?
    /// The grant of a line: its consent kind and label (`Store.grantID`), for example `whatsapp:<chat>`.
    public var grant: String?
    /// Every grant that starts with this text, for example `whatsapp:` for every chat of one consent kind.
    public var grantPrefix: String?
    /// Lines whose `last_seen` is before this moment.
    public var lastSeenBefore: Date?
    /// Lines the source tied to these ids of its own (`message_ref`).
    public var messageRefs: [String]?

    public init(
        source: SourceID? = nil, grant: String? = nil, grantPrefix: String? = nil, lastSeenBefore: Date? = nil,
        messageRefs: [String]? = nil
    ) {
        self.source = source
        self.grant = grant
        self.grantPrefix = grantPrefix
        self.lastSeenBefore = lastSeenBefore
        self.messageRefs = messageRefs
    }

    /// The erasure of one chat, as a revoke of that chat asks for.
    public static func grant(kind: SourceKind, label: String) -> EvidenceErasure {
        EvidenceErasure(grant: Store.grantID(kind: kind, label: label))
    }

    /// The erasure of the screen lines made from these activity rows: a window's stretch and the text it showed.
    static func screenRows(_ ids: [Int64]) -> EvidenceErasure {
        EvidenceErasure(
            grantPrefix: Store.grantID(kind: .screen, label: ""),
            messageRefs: ids.flatMap { [ScreenEvidence.windowMark + String($0), ScreenEvidence.textMark + String($0)] })
    }

    /// The erasure of one consent kind, older than `cutoff` when given. Without an age the cursors go too.
    public static func kind(_ kind: SourceKind, before cutoff: Date?) -> EvidenceErasure {
        EvidenceErasure(grantPrefix: Store.grantID(kind: kind, label: ""), lastSeenBefore: cutoff)
    }
}

/// What an erasure removes, or would remove.
public struct EraseCounts: Sendable, Equatable {
    public var lines = 0
    public var views = 0
    public var legacyCitations = 0
    public var searchEntries = 0
    /// Saved cursors. A cursor goes with its lines, so a new consent reads the chat again from the start; an erasure
    /// by age keeps them.
    public var cursors = 0
    /// Facts (`item` rows) that cite an erased line through an old citation id. They stay, flagged, without their
    /// quote; the run text and summaries that held the words go with it (`eraseCopies`).
    public var citingFacts = 0
}

extension Store {
    /// What `eraseEvidence` would remove. Changes nothing.
    public func previewEvidenceErasure(_ erasure: EvidenceErasure) throws -> EraseCounts {
        try writer.read { db in try Self.counts(of: erasure, in: db) }
    }

    /// The one erase path of evidence, also run by `delete`: the lines and every row that points at them go, and the
    /// log and the backups go (`finishErase`). Returns what was removed, the same counts the preview gave.
    @discardableResult
    public func eraseEvidence(_ erasure: EvidenceErasure) throws -> EraseCounts {
        let (counts, changed) = try writeCountingChanges { db in try Self.eraseEvidence(erasure, in: db) }
        try finishErase(removedRows: changed)
        return counts
    }

    /// Erases the copies of the lines' words, deletes the lines, their dependents and (unless the erasure has an age)
    /// their cursors, then optimizes the
    /// search index so no old segment keeps a word. With `secure_delete` on every connection, the caller's
    /// `finishErase` after the transaction leaves no copy in the file or its log.
    static func eraseEvidence(_ erasure: EvidenceErasure, in db: Database) throws -> EraseCounts {
        let counts = try counts(of: erasure, in: db)
        let condition = try condition(of: erasure)
        for key in try cursorKeys(of: erasure, condition, in: db) {
            try db.execute(sql: "DELETE FROM state WHERE key = ?", arguments: [key])
        }
        for grant in try erasedGrants(of: erasure, condition, in: db) {
            try db.execute(sql: "DELETE FROM state WHERE key = ?", arguments: [agreementKey(grantID: grant)])
            try db.execute(sql: "DELETE FROM pending_revoke WHERE grant_id = ?", arguments: [grant])
        }
        if counts.lines > 0 {
            try eraseCopies(
                of: LineSelection(
                    sql: "SELECT line_id FROM evidence WHERE \(condition.sql)", arguments: condition.arguments),
                in: db)
        }
        try db.execute(sql: "DELETE FROM evidence WHERE \(condition.sql)", arguments: condition.arguments)
        try EvidenceStamp.dropOrphanStructure(in: db)
        if counts.lines > 0 { try EvidenceStamp.optimizeSearch(in: db) }
        return counts
    }

    private struct Condition {
        var sql: String
        var arguments: StatementArguments
    }

    private static func condition(of erasure: EvidenceErasure) throws -> Condition {
        var parts: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        if let source = erasure.source {
            parts.append("source_id = ?")
            arguments.append(Data(source.bytes))
        }
        if let grant = erasure.grant {
            parts.append("grant_id = ?")
            arguments.append(grant)
        }
        if let prefix = erasure.grantPrefix {
            parts.append("substr(grant_id, 1, length(?)) = ?")
            arguments += [prefix, prefix]
        }
        if let cutoff = erasure.lastSeenBefore {
            parts.append("last_seen < ?")
            arguments.append(UTCInstant(cutoff).milliseconds)
        }
        if let refs = erasure.messageRefs {
            parts.append("message_ref IN (SELECT value FROM json_each(?))")
            arguments.append(try Coding.json(refs))
        }
        guard !parts.isEmpty else { throw EvidenceError.erasureNamesNothing }
        return Condition(sql: parts.joined(separator: " AND "), arguments: StatementArguments(arguments))
    }

    /// The cursors of the grants whose lines go, of the named grant even when it has no line, and of every grant with
    /// the named prefix. The note that old ids were mapped (`legacyKey`) is never removed.
    private static func cursorKeys(of erasure: EvidenceErasure, _ condition: Condition, in db: Database) throws
        -> Set<String>
    {
        guard erasure.lastSeenBefore == nil, erasure.messageRefs == nil else { return [] }
        var grants = try Set(
            String.fetchAll(
                db, sql: "SELECT DISTINCT grant_id FROM evidence WHERE \(condition.sql)",
                arguments: condition.arguments))
        if let grant = erasure.grant { grants.insert(grant) }
        var keys = Set(grants.map { cursorKey(grantID: $0) })
        if let prefix = erasure.grantPrefix {
            let start = cursorKey(grantID: prefix)
            keys.formUnion(
                try String.fetchAll(
                    db, sql: "SELECT key FROM state WHERE substr(key, 1, length(?)) = ?", arguments: [start, start]))
        }
        return keys
    }

    /// The grants that go with the cursors. A chat taken off the list also loses its confirmed audience and its noted deletions.
    private static func erasedGrants(of erasure: EvidenceErasure, _ condition: Condition, in db: Database) throws
        -> Set<String>
    {
        Set(try cursorKeys(of: erasure, condition, in: db).map { String($0.dropFirst(cursorKey(grantID: "").count)) })
    }

    private static func counts(of erasure: EvidenceErasure, in db: Database) throws -> EraseCounts {
        let condition = try condition(of: erasure)
        let selected = "SELECT line_id FROM evidence WHERE \(condition.sql)"
        func count(_ sql: String) throws -> Int {
            try Int.fetchOne(db, sql: sql, arguments: condition.arguments) ?? 0
        }
        var counts = EraseCounts()
        counts.lines = try count("SELECT count(*) FROM evidence WHERE \(condition.sql)")
        counts.views = try count("SELECT count(*) FROM evidence_view WHERE line_id IN (\(selected))")
        counts.legacyCitations = try count("SELECT count(*) FROM evidence_legacy WHERE line_id IN (\(selected))")
        counts.searchEntries = try count(
            "SELECT count(*) FROM evidence_fts_docsize WHERE id IN (SELECT id FROM evidence WHERE \(condition.sql))")
        counts.citingFacts = try LegacySpace.byKind.reduce(0) { total, pair in
            total
                + (try Int.fetchOne(
                    db,
                    sql: """
                        SELECT count(*) FROM item WHERE source = ? AND EXISTS (
                            SELECT 1 FROM evidence_legacy WHERE space = ? AND ref BETWEEN item.cite_first AND item.cite_last
                                AND line_id IN (\(selected)))
                        """,
                    arguments: StatementArguments([pair.0.rawValue, pair.1.rawValue]) + condition.arguments) ?? 0)
        }
        for key in try cursorKeys(of: erasure, condition, in: db)
        where try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM state WHERE key = ?)", arguments: [key]) == true
        {
            counts.cursors += 1
        }
        return counts
    }
}
