import Foundation
import GRDB
import Kernel

/// Claims and their checks are items, so marks, privacy deletes and the retention treat them like every other fact: a
/// claim has the source of the line it rests on, a check rests on web pages (source `web`).
extension Store {
    static let checkTask = "vc.claim-checks"

    /// Keeps claims. The grant is the consent the lines they rest on needed, and its kind is their source. A claim a
    /// person typed has no run.
    @discardableResult
    public func saveClaims(_ claims: [Claim], run: RunID?, grant: CaptureGrant) throws -> [Int64] {
        try check(grant, kind: grant.kind)
        let now = clock()
        return try writer.write { db in
            try claims.map { claim in
                let fields = [
                    Claim.dealField: claim.deal, "text": claim.text, "type": claim.type, "value": claim.value,
                ]
                return try insertItem(
                    db, task: Claim.task, run: run, source: grant.kind, cite: claim.line, fields: fields,
                    quote: claim.quote, label: claim.label, authority: claim.authority, at: now)
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

    func insertItem(
        _ db: Database, task: String, run: RunID?, source: SourceKind, cite: Int64, fields: [String: String],
        quote: String, label: Label? = nil, authority: Authority = .unknown, at now: Date
    ) throws -> Int64 {
        try Self.insertItem(
            db,
            Item(
                task: task, day: WorkDay(containing: now), scope: "", source: source, citeFirst: cite, citeLast: cite,
                start: now, end: now, fields: fields, quote: quote, run: run, label: label,
                authority: authority),
            at: now)
    }

    /// The claims of a deal the founder chose to check. Choosing again replaces the choice.
    public func choose(claims ids: [Int64], deal: String) throws {
        try saveState(try Coding.json(ids), forKey: Self.chosenKey(deal))
    }

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
                SELECT id, cite_first, fields, quote, label, source FROM item WHERE task = ? AND json_extract(fields, '$.deal') = ?
                ORDER BY id
                """, [Claim.task, deal]
            ) { row in
                let fields: [String: String] = try row.json("fields")
                return Claim(
                    id: try row.value("id"), deal: deal, text: fields["text"] ?? "",
                    type: fields["type"] ?? "", value: fields["value"] ?? "",
                    quote: try row.value("quote"), line: try row.value("cite_first"),
                    label: try row.optionalValue("label").map { (text: String) in
                        try Coding.value(StoredLabel.self, from: text).label()
                    }, source: try row.enumeration("source"))
            }
        }
    }

    /// The claim types of the first machine that lists any; nil when no machine does.
    public func claimTypes() throws -> [ClaimType]? { try machines().lazy.compactMap(\.spec.claimTypes).first }

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
