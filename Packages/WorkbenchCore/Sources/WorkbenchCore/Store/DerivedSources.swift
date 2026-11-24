import Foundation
import GRDB
import Lines

/// What each kind of node was made from, read from the rows that exist. The writers call these in the transaction that
/// writes the node, and the backfill calls the same functions for the nodes that were written before `derivation`
/// existed, so an edge means one thing whichever wrote it.
enum DerivedSources {
    /// The lines an item cites, one `supports` edge each, from the numbers `cite_first...cite_last` in the window of its
    /// run; the line of its quote, one `quotes` edge (all of them when the quote names no line). A fact the person typed has no run: its quote line is the evidence
    /// row it names. A fact made before runs kept their windows cites the old ids of its chat. The run of such a fact
    /// holds words of those lines too, so the run is a node with the same lines as sources.
    static func ofItem(_ id: Int64, in db: Database) throws -> [Derivation] {
        guard
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT task, run_id, source, scope, cite_first, cite_last, quote_line FROM item WHERE id = ?
                    """, arguments: [id])
        else { return [] }
        let task: String = row["task"]
        let node = Node(.item, id)
        let quoteNumber: Int64? = row["quote_line"]
        guard let run: RunID = row["run_id"] else {
            let quoted = try quoteNumber.flatMap {
                try Data.fetchOne(db, sql: "SELECT line_id FROM evidence WHERE id = ?", arguments: [$0])
            }
            return [
                Derivation(node: node, sources: quoted.map { [Source.quotes(.line($0))] } ?? [], run: nil, rule: task)
            ]
        }
        guard try hasWindow(run, in: db) else {
            let lines = try legacyLines(
                of: row["source"], scope: row["scope"], from: row["cite_first"], through: row["cite_last"], in: db)
            return [
                Derivation(node: node, sources: edges(cited: lines, quoted: nil), run: run, rule: task),
                Derivation(node: Node(.run, run), sources: lines.map { .quotes(.line($0)) }, run: run, rule: task),
            ]
        }
        let cited = try Data.fetchAll(
            db, sql: "SELECT line_id FROM run_line WHERE run_id = ? AND ordinal BETWEEN ? AND ?",
            arguments: [run, row["cite_first"] as Int64, row["cite_last"] as Int64])
        let quoted = try quoteNumber.flatMap { try lineAt($0, of: run, in: db) }
        return [Derivation(node: node, sources: edges(cited: cited, quoted: quoted), run: run, rule: task)]
    }

    /// A fact rests on every line it cites. It quotes the line its quote names; a fact whose quote does not name its line
    /// may hold words of any line it cites, so it quotes them all.
    private static func edges(cited: [Data], quoted: Data?) -> [Source] {
        cited.map { .supports(.line($0)) } + (quoted.map { [.quotes(.line($0))] } ?? cited.map { .quotes(.line($0)) })
    }

    /// The words a model event copied: the line it names, by its number in the window of its run, or by the old id of the
    /// chat of its fact when the run has no window. The event that opens a fact holds the quote of the fact, so it also
    /// quotes the fact.
    static func ofEvent(_ id: Int64, in db: Database) throws -> [Derivation] {
        guard
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT ev.item_id, ev.kind, ev.line_id, ev.run_id, item.task, item.source, item.scope
                    FROM item_event ev JOIN item ON item.id = ev.item_id
                    WHERE ev.id = ? AND ev.actor = 'model' AND ev.quote <> ''
                    """, arguments: [id])
        else { return [] }
        let run: RunID = row["run_id"]
        let number: Int64 = row["line_id"]
        let node = Node(.itemEvent, id)
        var sources: [Source] = []
        var runSources: [Source] = []
        if try hasWindow(run, in: db) {
            sources = try lineAt(number, of: run, in: db).map { [Source.quotes(.line($0))] } ?? []
        } else {
            let lines = try legacyLines(of: row["source"], scope: row["scope"], from: number, through: number, in: db)
            sources = lines.map { Source.quotes(.line($0)) }
            runSources = sources
        }
        if (row["kind"] as String) == EventKind.open.rawValue {
            sources.append(.quotes(Node(.item, row["item_id"] as Int64)))
        }
        let rule: String = row["task"]
        return [Derivation(node: node, sources: sources, run: run, rule: rule)]
            + (runSources.isEmpty ? [] : [Derivation(node: Node(.run, run), sources: runSources, run: run, rule: rule)])
    }

    /// The opening event of a fact, which the `item_opens` trigger writes with the fact.
    static func ofOpening(of item: Int64, in db: Database) throws -> [Derivation] {
        guard
            let event = try Int64.fetchOne(
                db, sql: "SELECT id FROM item_event WHERE item_id = ? AND kind = 'open'", arguments: [item])
        else { return [] }
        return try ofEvent(event, in: db)
    }

    /// A summary is made from the items of its day and machine that hold the value its scope names. The run that wrote
    /// it read their words, so the run is a node with the same items as sources.
    static func ofSummary(
        day: String, task: String, field: String, scope: String, run: RunID?, in db: Database
    ) throws -> [Derivation] {
        let items = try Int64.fetchAll(
            db,
            sql: """
                SELECT item.id FROM item WHERE item.day = ? AND item.task = ? AND EXISTS (
                    SELECT 1 FROM json_each(item.fields) AS field WHERE field.key || ': ' || field.value = ?)
                """, arguments: [day, task, scope])
        let sources = items.map { Source.quotes(Node(.item, $0)) }
        let summary = Derivation(
            node: Node(.summary, try summaryKey(day: day, task: task, field: field, scope: scope, in: db)),
            sources: sources,
            run: run, rule: "summary")
        guard let run else { return [summary] }
        return [summary, Derivation(node: Node(.run, run), sources: sources, run: run, rule: "summary")]
    }

    /// The key of a summary: its day, machine, grouping field and scope, as the store writes them in a JSON array.
    private static func summaryKey(day: String, task: String, field: String, scope: String, in db: Database) throws
        -> String
    {
        try String.fetchOne(db, sql: "SELECT json_array(?,?,?,?)", arguments: [day, task, field, scope]) ?? ""
    }

    /// The words of one of Mochi's proposals come from what its run read, so the proposal quotes its run.
    static func ofProposal(_ id: Int64, in db: Database) throws -> Derivation {
        let run = try RunID.fetchOne(db, sql: "SELECT run_id FROM proposal WHERE id = ?", arguments: [id])
        return Derivation(
            node: Node(.proposal, id), sources: run.map { [Source.quotes(Node(.run, $0))] } ?? [], run: run,
            rule: "mochi")
    }

    /// A log entry that names a fact holds words of it (a reminder's title, the person a draft was for).
    static func ofAction(_ id: Int64, in db: Database) throws -> Derivation {
        let item = try Int64.fetchOne(
            db,
            sql: """
                SELECT item.id FROM action JOIN item ON item.id = json_extract(action.detail, '$.item')
                WHERE action.id = ?
                """, arguments: [id])
        return Derivation(
            node: Node(.action, id), sources: item.map { [Source.quotes(Node(.item, $0))] } ?? [], run: nil,
            rule: "action")
    }

    /// A link event copies the quote and the fields of the fact it links, as the author's store had them.
    static func ofWorkEvent(_ id: Int64, in db: Database) throws -> Derivation {
        let item = try Int64.fetchOne(
            db,
            sql: """
                SELECT item.id FROM work_event JOIN item ON item.id = json_extract(work_event.body, '$.item.itemID')
                    AND item.task IS json_extract(work_event.body, '$.item.task')
                WHERE work_event.id = ?
                """, arguments: [id])
        return Derivation(
            node: Node(.workEvent, id), sources: item.map { [Source.quotes(Node(.item, $0))] } ?? [], run: nil,
            rule: "work-event")
    }

    /// A block holds words of every line and fact it cites.
    static func ofBlock(_ id: String, in db: Database) throws -> Derivation {
        let cites = try Row.fetchAll(
            db, sql: "SELECT item_id, line_id FROM machine_block_cite WHERE block_id = ? ORDER BY position",
            arguments: [id])
        let sources = cites.flatMap { cite -> [Source] in
            [.quotes(.line(cite["line_id"]))] + (cite["item_id"] as Int64?).map { [.quotes(Node(.item, $0))] }.orEmpty
        }
        let run = try RunID.fetchOne(db, sql: "SELECT made_by_run FROM machine_block WHERE id = ?", arguments: [id])
        return Derivation(node: Node(.machineBlock, id), sources: sources, run: run, rule: "machine-block")
    }

    /// The note of a page proposal holds words of the request that asked for it and of the blocks it brought in.
    static func ofPageProposal(_ id: Int64, in db: Database) throws -> Derivation {
        let row = try Row.fetchOne(
            db, sql: "SELECT request_line, run_id FROM page_proposal WHERE id = ?", arguments: [id])
        let blocks = try String.fetchAll(
            db, sql: "SELECT id FROM machine_block WHERE proposal_id = ? ORDER BY id", arguments: [id])
        let sources =
            (row.map { [Source.quotes(.line($0["request_line"]))] } ?? [])
            + blocks.map { .quotes(Node(.machineBlock, $0)) }
        return Derivation(node: Node(.pageProposal, id), sources: sources, run: row?["run_id"], rule: "page-proposal")
    }

    /// The lines and pages one claim cites: the claim's fact and each of its cites hold words of them.
    static func ofClaim(_ claim: Int64, in db: Database) throws -> [Derivation] {
        guard
            let item = try Int64.fetchOne(
                db, sql: "SELECT item_id FROM product_claim WHERE id = ?", arguments: [claim])
        else { return [] }
        let cites = try claimCites(where: "claim_cite.claim_id = ?", [claim], in: db)
        let sources = cites.map { Source.quotes($0.source) }
        let fact = Derivation(node: Node(.item, item), sources: sources, run: nil, rule: "judge-claim")
        return [fact]
            + cites.map {
                Derivation(node: Node(.claimCite, $0.id), sources: [.quotes($0.source)], run: nil, rule: "judge-cite")
            }
    }

    /// A work product holds the words of every claim of it, so it quotes every source its claims cite.
    static func ofProduct(_ id: Int64, in db: Database) throws -> Derivation {
        let cites = try claimCites(
            where: "claim_cite.claim_id IN (SELECT id FROM product_claim WHERE product_id = ?)", [id], in: db)
        let run = try RunID.fetchOne(db, sql: "SELECT run_id FROM work_product WHERE id = ?", arguments: [id])
        return Derivation(
            node: Node(.workProduct, id), sources: cites.map { .quotes($0.source) }, run: run, rule: "work-product")
    }

    /// A verdict holds words of its product, and of its claim when it judged one.
    static func ofVerdict(_ id: Int64, in db: Database) throws -> Derivation {
        let row = try Row.fetchOne(
            db,
            sql: """
                SELECT verdict.product_id, claim.item_id, verdict.run_id FROM judge_verdict verdict
                LEFT JOIN product_claim claim ON claim.id = verdict.claim_id WHERE verdict.id = ?
                """, arguments: [id])
        let product = row.map { [Source.quotes(Node(.workProduct, $0["product_id"] as Int64))] } ?? []
        let claim = (row?["item_id"] as Int64?).map { [Source.quotes(Node(.item, $0))] } ?? []
        return Derivation(
            node: Node(.judgeVerdict, id), sources: product + claim, run: row?["run_id"], rule: "judge-verdict")
    }

    /// The text a person edited a product into holds words of the product.
    static func ofProductMark(_ id: Int64, in db: Database) throws -> Derivation {
        let product = try Int64.fetchOne(
            db, sql: "SELECT product_id FROM product_mark WHERE id = ? AND edited_text IS NOT NULL", arguments: [id])
        return Derivation(
            node: Node(.productMark, id), sources: product.map { [.quotes(Node(.workProduct, $0))] } ?? [], run: nil,
            rule: "product-mark")
    }

    private static func hasWindow(_ run: RunID, in db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM run_line WHERE run_id = ?)", arguments: [run]) == true
    }

    private static func lineAt(_ ordinal: Int64, of run: RunID, in db: Database) throws -> Data? {
        try Data.fetchOne(
            db, sql: "SELECT line_id FROM run_line WHERE run_id = ? AND ordinal = ?", arguments: [run, ordinal])
    }

    /// The lines an old citation names: the ids `first...last` of the old space of the source kind, restricted to the
    /// chat of the fact, because old row numbers are global.
    private static func legacyLines(
        of kind: String, scope: String, from first: Int64, through last: Int64, in db: Database
    ) throws -> [Data] {
        guard let space = LegacySpace.byKind.first(where: { $0.0.rawValue == kind })?.1 else { return [] }
        return try Row.fetchAll(
            db,
            sql: """
                SELECT l.line_id, e.container FROM evidence_legacy l JOIN evidence e ON e.line_id = l.line_id
                WHERE l.space = ? AND l.ref BETWEEN ? AND ?
                """, arguments: [space.rawValue, first, last]
        ).filter { scope.isEmpty || WhatsAppJID.canonical(scope) == ($0["container"] as String) }.map { $0["line_id"] }
    }

    private struct Cite {
        var id: Int64
        var source: Node
    }

    private static func claimCites(where condition: String, _ arguments: StatementArguments, in db: Database) throws
        -> [Cite]
    {
        try Row.fetchAll(
            db,
            sql: """
                SELECT id, kind, line_id, snapshot_id FROM claim_cite WHERE \(condition) ORDER BY id
                """, arguments: arguments
        ).compactMap { row in
            let source: Node? =
                (row["kind"] as String) == "line"
                ? .line(row["line_id"]) : (row["snapshot_id"] as Int64?).map { Node(.snapshot, $0) }
            return source.map { Cite(id: row["id"], source: $0) }
        }
    }
}

extension Optional where Wrapped: Sequence {
    fileprivate var orEmpty: [Wrapped.Element] { map(Array.init) ?? [] }
}
