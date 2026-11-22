import Foundation
import GRDB
import Lines

/// The one place that maps an old citation id to lines (`evidence_legacy`) and reads the map back (research E-R2 §4.2,
/// research 56 §1 Legacy citations row). `item.id`, `cite_first`, `cite_last` and `item_event.line_id` are never
/// rewritten; an old citation resolves through this map, and a citation with no row in it is unresolved, not deleted.
enum LegacyCitations {
    struct Row: Equatable {
        var space: String
        var ref: Int64
        var ord: Int64

        init(space: String, ref: Int64, ord: Int64) {
            self.space = space
            self.ref = ref
            self.ord = ord
        }

        init(_ citation: LegacyRef) { self.init(space: citation.space.rawValue, ref: citation.ref, ord: 0) }
    }

    /// Maps an old id to a line. A row is written once: the first line to take an id keeps it, so an edit of a
    /// message does not move the citations that quoted its first text.
    static func map(_ row: Row, to lineID: Data, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO evidence_legacy(space, ref, ord, line_id)
                SELECT ?, ?, ?, ? WHERE NOT EXISTS (
                    SELECT 1 FROM evidence_legacy WHERE space = ? AND ref = ? AND ord = ?)
                """,
            arguments: [row.space, row.ref, row.ord, lineID, row.space, row.ref, row.ord])
    }

    /// The old ids that point at the text lines a revoke erases.
    static func refs(erasedBy revoke: Revoke, in db: Database) throws -> [Row] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT space, ref, ord FROM evidence_legacy WHERE line_id IN (
                    SELECT line_id FROM evidence WHERE \(Revoke.erased))
                """, arguments: revoke.arguments)
    }

    /// The text and kind of the lines that old ids in `refs` of one space point at. A fact of one chat (`scope` not
    /// empty) sees only lines of that chat: row numbers are global, so a range holds rows of other chats too.
    static func lines(in space: LegacySpace, refs: ClosedRange<Int64>, scope: String, db: Database) throws
        -> [CitedLine]
    {
        try CitedLine.fetchAll(
            db,
            sql: """
                SELECT evidence.text, evidence.tombstone FROM evidence_legacy
                JOIN evidence ON evidence.line_id = evidence_legacy.line_id
                WHERE evidence_legacy.space = ? AND evidence_legacy.ref BETWEEN ? AND ?
                    AND (? = '' OR evidence.container = ?)
                ORDER BY evidence_legacy.ref, evidence_legacy.ord
                """, arguments: [space.rawValue, refs.lowerBound, refs.upperBound, scope, scope])
    }

    static func isMapped(_ ref: Int64, in space: LegacySpace, db: Database) throws -> Bool {
        try Bool.fetchOne(
            db, sql: "SELECT EXISTS (SELECT 1 FROM evidence_legacy WHERE space = ? AND ref = ?)",
            arguments: [space.rawValue, ref]) ?? false
    }

    struct CitedLine: Equatable, FetchableRecord {
        var text: String
        var isTombstone: Bool

        init(row: GRDB.Row) {
            text = row["text"]
            isTombstone = row["tombstone"] == 1
        }
    }
}

extension LegacyCitations.Row: FetchableRecord {
    init(row: GRDB.Row) {
        self.init(space: row["space"], ref: row["ref"], ord: row["ord"])
    }
}

/// How many old WhatsApp citations resolve, counted from the store as it is. Nothing is changed or deleted.
public struct LegacyCitationReport: Sendable, Equatable {
    /// Facts from WhatsApp that cite a line.
    public var facts = 0
    /// Facts where at least one cited row maps to a line.
    public var resolved = 0
    /// Resolved facts whose quote is in the text of a mapped line.
    public var quoteChecked = 0
    /// Resolved facts whose quote is in no mapped line (the message changed, or the model saw another spelling).
    public var quoteNotFound = 0
    /// Resolved facts whose mapped lines are all tombstones: the message was deleted for everyone.
    public var revoked = 0
    /// Facts where no cited row maps to a line. They stay, marked "legacy cite, not found at source".
    public var unresolved = 0
    /// Distinct cited rows (the first and last of each fact), and how many of them map to no line.
    public var refs = 0
    public var refsUnresolved = 0
}

extension Store {
    /// Resolves every old WhatsApp citation through `evidence_legacy` and checks its quote against the line text.
    /// Run it after the first read of the chats the facts came from, while their row numbers still match.
    public func checkLegacyWhatsAppCitations() throws -> LegacyCitationReport {
        try writer.read { db in
            let facts = try Row.fetchAll(
                db,
                sql:
                    "SELECT cite_first, cite_last, quote, scope FROM item WHERE source = ? AND cite_first > 0 ORDER BY id",
                arguments: [SourceKind.whatsapp.rawValue])
            var report = LegacyCitationReport()
            var cited: Set<Int64> = []
            for fact in facts {
                let first: Int64 = fact["cite_first"]
                let last: Int64 = max(fact["cite_last"], first)
                let quote: String = fact["quote"]
                cited.formUnion([first, last])
                let scope: String = fact["scope"]
                let lines = try LegacyCitations.lines(
                    in: .whatsAppRow, refs: first...last, scope: WhatsAppJID.canonical(scope), db: db)
                report.facts += 1
                if lines.isEmpty {
                    report.unresolved += 1
                } else {
                    report.resolved += 1
                    if lines.allSatisfy(\.isTombstone) {
                        report.revoked += 1
                    } else if lines.contains(where: { $0.text.contains(quote: quote) }) {
                        report.quoteChecked += 1
                    } else {
                        report.quoteNotFound += 1
                    }
                }
            }
            report.refs = cited.count
            for ref in cited where try !LegacyCitations.isMapped(ref, in: .whatsAppRow, db: db) {
                report.refsUnresolved += 1
            }
            return report
        }
    }
}
