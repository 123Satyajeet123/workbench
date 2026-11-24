import Foundation
import GRDB
import Kernel
import Lines

/// The line a fact quotes, and where in it.
struct QuotedLine {
    var line: Data
    var span: Range<Int>
}

/// A stored machine block as a query reads it.
private struct BlockRow {
    var id: MachineBlockID
    var block: MachineBlock
    var label: Label?
    var erased: Bool

    init(row: Row) throws {
        guard let id = MachineBlockID(try row.value("id") as String) else { throw StoredValueError("id") }
        self.id = id
        block = try row.json("spec")
        label = try (row.optionalValue("label") as String?).flatMap {
            try? Coding.value(StoredLabel.self, from: $0).label()
        }
        erased = try row.value("words_erased") as Int == 1
    }
}

extension Queries {
    /// The page of a work object as `viewer` may read it: the order of its blocks, the live blocks of machines, the
    /// paragraphs of the person, and which machine blocks lost their words to an erase.
    public func page(of object: WorkObjectID, for viewer: PageViewer) throws -> PageContents {
        try reader.read { db in
            var contents = PageContents(page: MachinePage(), notes: [], erased: [])
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT mb.id, mb.spec, mb.label, mb.words_erased, e.message_ref AS paragraph, e.text
                    FROM container_order o
                    LEFT JOIN machine_block mb ON mb.entity_key = o.entity_key AND mb.state = 'live'
                    LEFT JOIN evidence e ON e.entity_key = o.entity_key AND e.id = (
                        SELECT v.id FROM evidence v WHERE v.entity_key = o.entity_key AND v.tombstone = 0
                        ORDER BY v.last_seen DESC, v.id DESC LIMIT 1)
                    WHERE o.container = ? ORDER BY o.position
                    """, arguments: [try Store.container(of: object)])
            {
                if (row["id"] as String?) != nil {
                    let stored = try BlockRow(row: row)
                    guard viewer.shows(stored.block, labelled: stored.label) else { continue }
                    contents.page.order.append(.machine(stored.id))
                    contents.page.blocks[stored.id] = stored.block
                    if stored.erased { contents.erased.insert(stored.id) }
                } else if let block = (row["paragraph"] as String?).flatMap(BlockID.init) {
                    contents.page.order.append(.note(block))
                    contents.notes.append(NoteBlock(id: block, text: row["text"]))
                }
            }
            return contents
        }
    }

    /// The proposal waiting on a page, with the blocks it brings in; nil when none waits.
    public func pendingProposal(of object: WorkObjectID, for viewer: PageViewer) throws -> PendingProposal? {
        try reader.read { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT id, machine_id, run_id, request_line, note, ops, at FROM page_proposal
                        WHERE object_id = ? AND state = 'pending'
                        """, arguments: [object])
            else { return nil }
            var proposal = PendingProposal(
                id: row["id"], machine: row["machine_id"], run: row["run_id"], requestLine: row["request_line"],
                note: row["note"], operations: try row.json("ops"), blocks: [:], erased: [], at: try row.date("at"))
            for block in try Row.fetchAll(
                db,
                sql: """
                    SELECT id, spec, label, words_erased FROM machine_block WHERE proposal_id = ? AND state = 'proposed'
                    """, arguments: [proposal.id]
            ).map(BlockRow.init(row:)) where viewer.shows(block.block, labelled: block.label) {
                proposal.blocks[block.id] = block.block
                if block.erased { proposal.erased.insert(block.id) }
            }
            return proposal
        }
    }

    /// The stored lines the words of `items` and of the paragraphs of a page rest on: what `PageComposer` records as
    /// its run's window, and what a cite of a fact or a paragraph stands for.
    public func pageGrounds(of object: WorkObjectID, items: [Item]) throws -> PageGrounds {
        try reader.read { db in
            PageGrounds(
                facts: try Self.quotedLines(db, ofFacts: items.compactMap(\.id)).mapValues(\.line),
                notes: try Self.paragraphLines(db, in: try Store.container(of: object)))
        }
    }

    static func pendingProposalID(_ db: Database, of object: WorkObjectID) throws -> PageProposalID? {
        try Int64.fetchOne(
            db, sql: "SELECT id FROM page_proposal WHERE object_id = ? AND state = 'pending'", arguments: [object])
    }

    /// The line each fact quotes: the line its run's window numbered `quote_line`. A fact whose quote is not from a
    /// line of a run's window has none.
    static func quotedLines(_ db: Database, ofFacts facts: [Int64]) throws -> [Int64: QuotedLine] {
        Dictionary(
            uniqueKeysWithValues: try Row.fetchAll(
                db,
                sql: """
                    SELECT item.id, w.line_id, item.quote_start, item.quote_end FROM item
                    JOIN run_line w ON w.run_id = item.run_id AND w.ordinal = item.quote_line
                    WHERE item.quote_start IS NOT NULL AND item.id IN (SELECT value FROM json_each(?))
                    """, arguments: [try Coding.json(facts)]
            ).map { ($0["id"] as Int64, QuotedLine(line: $0["line_id"], span: $0["quote_start"]..<$0["quote_end"])) })
    }

    /// The current line of each paragraph in the order of a container.
    static func paragraphLines(_ db: Database, in container: String) throws -> [BlockID: Data] {
        Dictionary(
            uniqueKeysWithValues: try Row.fetchAll(
                db,
                sql: """
                    SELECT e.message_ref, e.line_id FROM container_order o
                    JOIN evidence e ON e.entity_key = o.entity_key AND e.id = (
                        SELECT v.id FROM evidence v WHERE v.entity_key = o.entity_key AND v.tombstone = 0
                        ORDER BY v.last_seen DESC, v.id DESC LIMIT 1)
                    WHERE o.container = ? AND e.message_ref IS NOT NULL
                    """, arguments: [container]
            ).compactMap { row -> (BlockID, Data)? in
                BlockID(row["message_ref"] as String).map { ($0, row["line_id"] as Data) }
            })
    }

    static func storedLine(_ db: Database, id: Data) throws -> StoredLine? {
        try StoredLine.fetchAll(
            db, sql: "SELECT e.id AS number, \(StoredLine.columns) FROM evidence e WHERE e.line_id = ?",
            arguments: [id]
        ).first
    }
}
