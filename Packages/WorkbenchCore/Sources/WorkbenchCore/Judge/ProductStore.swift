import Foundation
import GRDB
import Kernel

/// The chance that a product is shown with one known-bad claim among its own: about one product in fifteen, inside the
/// range J3 gives (one in ten to one in twenty).
public enum CatchPolicy {
    public static let chance = 1.0 / 15
    public static let version = "catch-1"

    /// Draws the kind of catch to inject, or nil for none.
    @Sendable public static func draw(chance: Double) -> CatchKind? {
        Double.random(in: 0..<1) < chance ? CatchKind.allCases.randomElement() : nil
    }
}

/// A product as the store wrote it: its row, and a row for each claim in the order shown (a catch claim last).
public struct SavedProduct: Sendable, Equatable {
    public var id: Int64
    public var role: SplitRole
    public var claims: [SavedClaim]

    /// The product as the person is shown it: its claims in the order saved, a catch claim among them.
    public func shown(from product: WorkProduct) -> WorkProduct {
        var shown = product
        shown.claims = claims.map(\.content)
        return shown
    }
}

public struct SavedClaim: Sendable, Equatable {
    /// The `product_claim` row.
    public var id: Int64
    /// The item that carries the claim's marks.
    public var item: Int64
    public var isCatch: Bool
    public var content: ProductClaim
}

/// How a person marks a claim: right, wrong, or unsupported (it states something no cite backs). Wrong and unsupported
/// both count as wrong for the certificate.
public enum ClaimMark: String, Codable, Sendable, CaseIterable {
    case right, wrong, unsupported

    var mark: Mark { self == .right ? .confirmed : .rejected }
}

/// How a person marks a whole product: use it, edit it (the edited text is kept in full), or discard it.
public enum ProductMark: Sendable, Equatable {
    case use
    case edit(String)
    case discard

    var state: String {
        switch self {
        case .use: "use"
        case .edit: "edit"
        case .discard: "discard"
        }
    }

    var editedText: String? {
        if case .edit(let text) = self { text } else { nil }
    }
}

extension Store {
    static func claimTask(of taskType: String) -> String { taskType + ".claim" }
    static func catchTask(of taskType: String) -> String { taskType + ".catch" }

    /// Keeps a fetched page once, with the hash of its text and the date it states. A page with the same address and
    /// text is the same snapshot. The session proves the web consent was on when the page was fetched.
    @discardableResult
    public func savePageSnapshot(_ page: FetchedPage, pageDate: Date? = nil, session: WebSession) throws -> Int64 {
        try check(session.grant, kind: .web)
        let now = clock()
        let hash = Digest.sha256(page.text)
        let stated = pageDate ?? PageDate.stated(in: page.text)
        return try writer.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO page_snapshot(url, fetched_at, content_hash, text, page_date)
                    VALUES (?,?,?,?,?)
                    """, arguments: [page.url.absoluteString, now.stored, hash, page.text, stated?.stored])
            return try Int64.fetchOne(
                db, sql: "SELECT id FROM page_snapshot WHERE url = ? AND content_hash = ?",
                arguments: [page.url.absoluteString, hash])!
        }
    }

    /// Keeps a work product with its claims, cites and versions, written once. Each claim is an item, so marks, audits and
    /// the certificate treat it like every fact: the app picks it to ask about with `AuditPolicy.pickChance`, and keeps
    /// that chance. With the chance `catchChance`, one known-bad claim is added on a run of its own, so it is shown like
    /// any other and counted apart. `split_role` is written here and never again.
    public func saveProduct(
        _ product: WorkProduct, writer run: RunID, grant: CaptureGrant, label: Label? = nil,
        versions: JudgeVersions, catchChance: Double = CatchPolicy.chance,
        draw: @Sendable (Double) -> CatchKind? = CatchPolicy.draw(chance:), isAudited: ((Int) -> Bool)? = nil
    ) throws -> SavedProduct {
        try check(grant, kind: grant.kind)
        let now = clock()
        let role = SplitRole(day: WorkDay(containing: now), freezes: try queries.freezes(of: product.taskType))
        let catches = draw(catchChance).flatMap { Self.catchClaim(for: product, kind: $0) }
        return try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO work_product(task_type, object_id, subject, run_id, source, text, created_at, split_role,
                        catch_chance, versions) VALUES (?,?,?,?,?,?,?,?,?,?)
                    """,
                arguments: [
                    product.taskType, product.object, product.subject, run, grant.kind.rawValue, product.text,
                    now.stored, role.rawValue, catchChance, try Coding.json(versions.parts),
                ])
            let id = db.lastInsertedRowID
            var saved: [SavedClaim] = []
            for (index, claim) in product.claims.enumerated() {
                let item = try Self.insertClaim(
                    db, claim, of: product, id: id, run: run, source: grant.kind, label: label, at: now)
                if audits(item: item, of: product.taskType, index: index, override: isAudited) {
                    try db.execute(
                        sql: "UPDATE item SET asked_with = ? WHERE id = ?", arguments: [AuditPolicy.pickChance, item])
                }
                saved.append(
                    try Self.insertProductClaim(db, product: id, ordinal: index, item: item, claim: claim, at: now))
            }
            if let (kind, claim) = catches {
                let catchRun = try Self.beginRun(
                    db, task: Self.catchTask(of: product.taskType), model: "catch",
                    prompt: Digest.sha256(CatchPolicy.version), input: "claims made wrong by code", kinds: [], at: now)
                try Self.finishRun(db, catchRun, model: "catch", usage: Usage(), reply: claim.text, at: now)
                let item = try Self.insertClaim(
                    db, claim, of: product, id: id, run: catchRun, source: grant.kind, label: label, at: now)
                saved.append(
                    try Self.insertProductClaim(
                        db, product: id, ordinal: product.claims.count, item: item, claim: claim, catching: kind,
                        at: now))
            }
            try Self.derive([try DerivedSources.ofProduct(id, in: db)], at: now, in: db)
            return SavedProduct(id: id, role: role, claims: saved)
        }
    }

    /// The catch claim for a product: made from the first claim that has a cite, in the given kind, or a sentence with no
    /// cite when that kind has nothing to change.
    private static func catchClaim(for product: WorkProduct, kind: CatchKind) -> (CatchKind, ProductClaim)? {
        guard let source = product.claims.first(where: { !$0.cites.isEmpty }) else { return nil }
        if let made = CatchClaim.make(from: source, kind: kind) { return (kind, made) }
        return CatchClaim.make(from: source, kind: .unsupported).map { (.unsupported, $0) }
    }

    private static func insertClaim(
        _ db: Database, _ claim: ProductClaim, of product: WorkProduct, id: Int64, run: RunID, source: SourceKind,
        label: Label?, at now: Date
    ) throws -> Int64 {
        try insertItem(
            db,
            Item(
                task: claimTask(of: product.taskType), day: WorkDay(containing: now), scope: "", source: source,
                citeFirst: 0, citeLast: 0, start: now, end: now,
                fields: [HelperSpec.Field.deal.name: product.object, "text": claim.text, "product": String(id)],
                quote: claim.cites.first?.quote ?? claim.text, run: run, label: label),
            at: now, origin: .deal)
    }

    private static func insertProductClaim(
        _ db: Database, product: Int64, ordinal: Int, item: Int64, claim: ProductClaim, catching kind: CatchKind? = nil,
        at now: Date
    ) throws -> SavedClaim {
        try db.execute(
            sql: """
                INSERT INTO product_claim(product_id, ordinal, item_id, shown_as, catch_kind, catch_truth)
                VALUES (?,?,?,?,?,?)
                """,
            arguments: [
                product, ordinal, item, kind == nil ? "real" : "catch", kind?.rawValue,
                kind == nil ? nil : CatchKind.truth,
            ])
        let id = db.lastInsertedRowID
        for (position, cite) in claim.cites.enumerated() { try insertCite(db, claim: id, ordinal: position, cite) }
        try derive(try DerivedSources.ofClaim(id, in: db), at: now, in: db)
        return SavedClaim(id: id, item: item, isCatch: kind != nil, content: claim)
    }

    private static func insertCite(_ db: Database, claim: Int64, ordinal: Int, _ cite: Cite) throws {
        let stored = try storedText(db, of: cite.source)
        let span = stored.text?.span(of: cite.quote)
        try db.execute(
            sql: """
                INSERT INTO claim_cite(claim_id, ordinal, kind, line_id, snapshot_id, content_hash, quote, span_start,
                    span_end) VALUES (?,?,?,?,?,?,?,?,?)
                """,
            arguments: [
                claim, ordinal, stored.kind, stored.line, stored.snapshot, stored.hash, cite.quote, span?.lowerBound,
                span?.upperBound,
            ])
    }

    /// What a cite's source holds now, with the columns that name it.
    private static func storedText(
        _ db: Database, of source: Cite.Source
    ) throws -> (kind: String, line: Data?, snapshot: Int64?, hash: String?, text: String?) {
        switch source {
        case .line(let id):
            let text = try String.fetchOne(db, sql: "SELECT text FROM evidence WHERE line_id = ?", arguments: [id])
            return ("line", id, nil, nil, text)
        case .page(let id):
            let row = try Row.fetchOne(
                db, sql: "SELECT content_hash, text FROM page_snapshot WHERE id = ?", arguments: [id])
            return ("page", nil, id, row?["content_hash"], row?["text"])
        }
    }

    /// Adds the verdicts of one judgment to the trace. Rows are never changed; a later judgment adds its own.
    public func saveJudgment(_ judgment: ProductJudgment, of product: SavedProduct) throws {
        let versions = try Coding.json(judgment.versions.parts)
        let now = clock().stored
        try writer.write { db in
            func add(_ verdict: StageVerdict, claim: Int64?) throws {
                try db.execute(
                    sql: """
                        INSERT INTO judge_verdict(product_id, claim_id, stage, rubric_item, verdict, reason, detail, score,
                            versions, run_id, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)
                        """,
                    arguments: [
                        product.id, claim, verdict.stage.rawValue, verdict.rubricItem, verdict.verdict.rawValue,
                        verdict.reason, verdict.detail, verdict.score, versions, verdict.run, now,
                    ])
                try Self.derive([try DerivedSources.ofVerdict(db.lastInsertedRowID, in: db)], at: clock(), in: db)
            }
            for (claim, judged) in zip(product.claims, judgment.claims) {
                try add(judged.structure, claim: claim.id)
                if let grounding = judged.grounding { try add(grounding, claim: claim.id) }
            }
            for advice in judgment.advice { try add(advice, claim: nil) }
            try add(
                StageVerdict(stage: .product, verdict: judgment.verdict, reason: judgment.verdict.rawValue),
                claim: nil)
        }
    }

    /// Marks a claim. A mark is a new row, and the latest is the claim's state. A claim the app picked to ask about
    /// gives an audit mark with the chance it had. A wrong or unsupported mark also records which.
    public func mark(claim: Int64, as mark: ClaimMark) throws {
        try writer.write { db in
            guard
                let item = try Int64.fetchOne(
                    db, sql: "SELECT item_id FROM product_claim WHERE id = ?", arguments: [claim])
            else { return }
            try addMark(db, item: item, mark.mark)
            if mark != .right {
                try db.execute(
                    sql: "INSERT INTO mark_reason(mark_id, reason) VALUES (?,?)",
                    arguments: [db.lastInsertedRowID, mark.rawValue])
            }
        }
    }

    /// Marks a product, where the person made the mark. An edit keeps its text in full.
    public func mark(product: Int64, as mark: ProductMark, surface: MarkSurface) throws {
        try writer.write { db in
            try db.execute(
                sql: "INSERT INTO product_mark(product_id, ts, state, edited_text, surface) VALUES (?,?,?,?,?)",
                arguments: [product, clock().stored, mark.state, mark.editedText, surface.rawValue])
            try Self.derive([try DerivedSources.ofProductMark(db.lastInsertedRowID, in: db)], at: clock(), in: db)
        }
    }
}

/// The date a page states about itself, from its text: the first date the platform finds near its start.
public enum PageDate {
    static let reach = 2_000

    public static func stated(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let head = String(text.prefix(reach))
        return detector.firstMatch(in: head, range: NSRange(head.startIndex..., in: head))?.date
    }
}
