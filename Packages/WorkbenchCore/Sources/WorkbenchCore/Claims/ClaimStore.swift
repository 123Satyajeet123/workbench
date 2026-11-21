import Foundation
import GRDB

/// Claims and their checks are items, so marks, privacy deletes and the retention treat them like every other fact: a
/// claim is read from the deck (source `mail`), a check rests on web pages (source `web`).
extension Store {
    static let checkTask = "vc.claim-checks"

    /// Keeps the claims a model read from a deck. The grant is the mail consent the reading needed.
    @discardableResult
    public func saveClaims(_ claims: [Claim], run: RunID, grant: CaptureGrant) throws -> [Int64] {
        try check(grant, kind: .mail)
        let now = clock()
        return try writer.write { db in
            try claims.map { claim in
                let fields = [
                    Claim.dealField: claim.deal, "text": claim.text, "type": claim.type.rawValue, "value": claim.value,
                ]
                return try insertItem(
                    db, task: Claim.task, run: run, source: .mail, cite: claim.line, fields: fields,
                    quote: claim.quote, at: now)
            }
        }
    }

    /// Keeps one check. The session proves the web consent was on when the pages were fetched.
    @discardableResult
    public func saveCheck(_ result: ClaimCheck, claimQuote: String, run: RunID, session: WebSession) throws -> Int64 {
        try check(session.grant, kind: .web)
        let now = clock()
        let fields = [
            Claim.dealField: result.deal, "claim": String(result.claim), "claim_text": result.claimText,
            "verdict": result.verdict.rawValue, "url": result.url, "evidence": result.quote.isEmpty ? "none" : "page",
        ]
        return try writer.write { db in
            try insertItem(
                db, task: Self.checkTask, run: run, source: .web, cite: result.claim, fields: fields,
                quote: result.quote.isEmpty ? claimQuote : result.quote, at: now)
        }
    }

    private func insertItem(
        _ db: Database, task: String, run: RunID, source: SourceKind, cite: Int64, fields: [String: String],
        quote: String, at now: Date
    ) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                    quote, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            arguments: [
                task, run, WorkDay(containing: now).description, "", source.rawValue, cite, cite, now.stored,
                now.stored, try Coding.json(fields), quote, now.stored,
            ])
        return db.lastInsertedRowID
    }

    /// The claims of a deal the founder chose to check. Choosing again replaces the choice.
    public func choose(claims ids: [Int64], deal: String) throws {
        try saveState(try Coding.json(ids), forKey: Self.chosenKey(deal))
    }

    /// The second mark of a check: is its quote right.
    public func markQuote(of item: Int64, as mark: Mark) throws {
        try writer.write { db in
            try db.execute(
                sql: "INSERT INTO quote_mark(item_id, ts, state) VALUES (?,?,?)",
                arguments: [item, clock().stored, mark.rawValue])
        }
    }

    static func chosenKey(_ deal: String) -> String { "claims.chosen." + deal }
}

extension Queries {
    public func claims(of deal: String) throws -> [Claim] {
        try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT id, cite_first, fields, quote FROM item WHERE task = ? AND json_extract(fields, '$.deal') = ?
                ORDER BY id
                """, [Claim.task, deal]
            ) { row in
                let fields: [String: String] = try row.json("fields")
                return Claim(
                    id: try row.value("id"), deal: deal, text: fields["text"] ?? "",
                    type: ClaimType(rawValue: fields["type"] ?? "") ?? .other, value: fields["value"] ?? "",
                    quote: try row.value("quote"), line: try row.value("cite_first"))
            }
        }
    }

    public func chosenClaims(of deal: String) throws -> [Int64] {
        try state(forKey: Store.chosenKey(deal)).flatMap { try? Coding.value([Int64].self, from: $0) } ?? []
    }

    /// The latest check of each claim of a deal, oldest claim first.
    public func claimChecks(of deal: String) throws -> [ClaimCheck] {
        let all = try reader.read { db in
            try db.fetch(
                "item",
                """
                SELECT id, fields, quote, state, created_at,
                    COALESCE((SELECT state FROM quote_mark WHERE item_id = item_mark.id ORDER BY id DESC LIMIT 1),
                        'proposed') AS quote_state
                FROM item_mark WHERE task = ? AND json_extract(fields, '$.deal') = ? ORDER BY id
                """, [Store.checkTask, deal]
            ) { row in
                let fields: [String: String] = try row.json("fields")
                var check = ClaimCheck(
                    id: try row.value("id"), claim: Int64(fields["claim"] ?? "") ?? 0, deal: deal,
                    claimText: fields["claim_text"] ?? "",
                    verdict: ClaimVerdict(rawValue: fields["verdict"] ?? "") ?? .unclear,
                    quote: fields["evidence"] == "page" ? try row.value("quote") : "", url: fields["url"] ?? "",
                    checkedAt: try row.date("created_at"))
                check.verdictMark = try row.enumeration("state")
                check.quoteMark = try row.enumeration("quote_state")
                return check
            }
        }
        let latest = Dictionary(all.map { ($0.claim, $0) }, uniquingKeysWith: { _, newer in newer })
        return latest.values.sorted { ($0.id ?? 0) < ($1.id ?? 0) }
    }
}
