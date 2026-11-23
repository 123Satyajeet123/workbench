import Foundation
import GRDB

/// The cited text of the store: stored lines and page snapshots.
public struct StoreCiteLibrary: CiteLibrary {
    let queries: Queries

    public init(_ queries: Queries) { self.queries = queries }

    public func text(of source: Cite.Source) throws -> CitedText? { try queries.citedText(of: source) }
}

/// A claim of a product as a page shows it: its words, what the judge decided at each stage, and the person's mark.
public struct JudgedClaim: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var item: Int64
    public var product: Int64
    public var text: String
    public var structure: StageVerdict?
    public var grounding: StageVerdict?
    public var mark: Mark
    /// Known to measurement only. A page shows a catch claim like any other.
    public var isCatch: Bool
}

/// A product with the marks of the person on it, for code that learns from them. Held-out products are never in it
/// unless the use is an evaluation.
public struct MarkedProduct: Sendable, Equatable {
    public struct Claim: Sendable, Equatable {
        public var text: String
        public var mark: Mark
    }

    public var id: Int64
    public var text: String
    public var role: SplitRole
    public var claims: [Claim]
    public var mark: String?
    /// The text the person edited it to, in full.
    public var editedText: String?
}

extension Queries {
    func citedText(of source: Cite.Source) throws -> CitedText? {
        try reader.read { db in
            switch source {
            case .line(let id):
                return try String.fetchOne(
                    db, sql: "SELECT text FROM evidence WHERE line_id = ? AND tombstone = 0", arguments: [id]
                ).map { CitedText(source: source, text: $0, origin: .line) }
            case .page(let id):
                return try db.fetch(
                    "page_snapshot",
                    "SELECT url, fetched_at, content_hash, text, page_date FROM page_snapshot WHERE id = ?",
                    [id]
                ) { row in
                    guard let url = URL(string: try row.value("url") as String) else { throw StoredValueError("url") }
                    return CitedText(
                        source: source, text: try row.value("text"),
                        origin: .page(
                            url: url, fetchedAt: try row.date("fetched_at"), contentHash: try row.value("content_hash"),
                            pageDate: try row.optionalDate("page_date")))
                }.first
            }
        }
    }

    /// The claims of the products of a deal, newest product first, with the latest verdict of each stage.
    public func judgedClaims(of deal: String) throws -> [JudgedClaim] {
        try reader.read { db in
            let verdicts = try db.fetch(
                "judge_now",
                """
                SELECT claim_id, stage, verdict, reason, detail, score, run_id FROM judge_now
                WHERE claim_id IN (SELECT c.id FROM product_claim c JOIN work_product p ON p.id = c.product_id
                    WHERE p.deal = ?) AND stage IN ('structure','grounding')
                """, [deal]
            ) { row -> (Int64, StageVerdict) in
                (
                    try row.value("claim_id"),
                    StageVerdict(
                        stage: try row.enumeration("stage"), verdict: try row.enumeration("verdict"),
                        reason: try row.value("reason"), detail: try row.value("detail"),
                        score: try row.optionalValue("score"), run: try row.optionalValue("run_id"))
                )
            }
            return try db.fetch(
                "product_claim",
                """
                SELECT c.id, c.item_id, c.product_id, c.shown_as, m.fields, m.state FROM product_claim c
                JOIN work_product p ON p.id = c.product_id JOIN item_mark m ON m.id = c.item_id
                WHERE p.deal = ? ORDER BY p.id DESC, c.ordinal
                """, [deal]
            ) { row in
                let id: Int64 = try row.value("id")
                let fields: [String: String] = try row.json("fields")
                let own = verdicts.filter { $0.0 == id }.map(\.1)
                return JudgedClaim(
                    id: id, item: try row.value("item_id"), product: try row.value("product_id"),
                    text: fields["text"] ?? "", structure: own.first { $0.stage == .structure },
                    grounding: own.first { $0.stage == .grounding }, mark: try row.enumeration("state"),
                    isCatch: try row.value("shown_as") as String == "catch")
            }
        }
    }

    /// The agreement of the judge with the person on the latest marks of `taskType`, over the claims the judge decided.
    /// The role is part of the call: a held-out read is refused to every use but an evaluation.
    public func judgeAgreement(taskType: String, split: SplitRole, for use: DataUse) throws -> JudgeAgreement {
        try HeldOutGuard.admit(split, for: use)
        return try reader.read { db in
            var agreement = JudgeAgreement()
            let rows = try db.fetch(
                "product_claim",
                """
                SELECT COALESCE(g.verdict, s.verdict) AS verdict, m.state AS state FROM product_claim c
                JOIN work_product p ON p.id = c.product_id JOIN item_mark m ON m.id = c.item_id
                JOIN judge_now s ON s.claim_id = c.id AND s.stage = 'structure'
                LEFT JOIN judge_now g ON g.claim_id = c.id AND g.stage = 'grounding'
                WHERE p.task_type = ? AND p.split_role = ? AND c.shown_as = 'real' AND m.state <> 'proposed'
                ORDER BY c.id DESC LIMIT ?
                """, [taskType, split.rawValue, PredictionPoweredInference.mostMarks]
            ) { row in (judge: try row.enumeration("verdict") as Verdict, person: try row.enumeration("state") as Mark)
            }
            for row in rows { agreement.add(judge: row.judge, person: row.person) }
            return agreement
        }
    }

    /// Products with their marks, for code that learns, tunes or analyses errors. The guard decides who reads held-out.
    public func markedProducts(taskType: String, split: SplitRole, for use: DataUse) throws -> [MarkedProduct] {
        try HeldOutGuard.admit(split, for: use)
        return try reader.read { db in
            try db.fetch(
                "work_product",
                """
                SELECT p.id, p.text, p.split_role, (SELECT state FROM product_mark WHERE product_id = p.id
                    ORDER BY id DESC LIMIT 1) AS mark, (SELECT edited_text FROM product_mark WHERE product_id = p.id
                    ORDER BY id DESC LIMIT 1) AS edited FROM work_product p
                WHERE p.task_type = ? AND p.split_role = ? ORDER BY p.id
                """, [taskType, split.rawValue]
            ) { row in
                let id: Int64 = try row.value("id")
                let claims = try db.fetch(
                    "product_claim",
                    """
                    SELECT m.fields, m.state FROM product_claim c JOIN item_mark m ON m.id = c.item_id
                    WHERE c.product_id = ? AND c.shown_as = 'real' ORDER BY c.ordinal
                    """, [id]
                ) { claim in
                    let fields: [String: String] = try claim.json("fields")
                    return MarkedProduct.Claim(text: fields["text"] ?? "", mark: try claim.enumeration("state"))
                }
                return MarkedProduct(
                    id: id, text: try row.value("text"), role: try row.enumeration("split_role"), claims: claims,
                    mark: try row.optionalValue("mark"), editedText: try row.optionalValue("edited"))
            }
        }
    }

    static let rungKey = "judge.rung."

    public func appliedRung(of taskType: String) throws -> Rung {
        try state(forKey: Self.rungKey + taskType).flatMap(Rung.init(rawValue:)) ?? .ask
    }

    /// The rung each prompt version of the writer has earned for `taskType`, newest first, beside the rung in force. The
    /// certificate is the one from held-out days that `quality()` computes: nothing here makes a number of its own.
    public func rungReports(of taskType: String, on day: WorkDay) throws -> [(quality: Quality, report: RungReport)] {
        let writerTasks = try reader.read { db in
            Set(
                try String.fetchAll(
                    db,
                    sql:
                        "SELECT DISTINCT r.task FROM work_product p JOIN run r ON r.id = p.run_id WHERE p.task_type = ?",
                    arguments: [taskType]))
        }
        let frozen = !(try freezes(of: taskType)).isEmpty
        let applied = try appliedRung(of: taskType)
        let open = try heldOutWindowIsOpen(of: taskType, on: day)
        return try quality().filter { writerTasks.contains($0.task) }.map {
            (
                $0,
                Autonomy.report(
                    certificate: $0.heldOutAudit, hasFrozenJudge: frozen, applied: applied, windowIsOpen: open)
            )
        }
    }
}

extension Store {
    /// The person sets the rung in force. Inside a held-out window of the task the rung does not change.
    public func applyRung(_ rung: Rung, to taskType: String) throws {
        guard !(try queries.heldOutWindowIsOpen(of: taskType, on: WorkDay(containing: clock()))) else {
            throw HeldOutRefusal.rungFrozen(taskType)
        }
        try saveState(rung.rawValue, forKey: Queries.rungKey + taskType)
    }
}
