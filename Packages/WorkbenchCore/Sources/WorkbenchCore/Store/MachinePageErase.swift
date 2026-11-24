import Foundation
import GRDB

extension Store {
    /// The blocks of a machine that rest on one of the lines, or on one of the facts the same erase flagged, whatever the
    /// state of the block (proposed, live, replaced or removed).
    static func blocksResting(on lines: LineSelection, orFacts facts: String, in db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: """
                SELECT DISTINCT block_id FROM machine_block_cite
                WHERE line_id IN (\(lines.sql)) OR item_id IN (SELECT value FROM json_each(?))
                """, arguments: lines.arguments + StatementArguments([facts]))
    }

    /// The page proposals that asked with one of the lines, or that brought in one of the blocks.
    static func pageProposalsAsking(from lines: LineSelection, orOf blocks: [String], in db: Database) throws -> [Int64]
    {
        try Int64.fetchAll(
            db,
            sql: """
                SELECT id FROM page_proposal WHERE request_line IN (\(lines.sql)) OR id IN (
                    SELECT proposal_id FROM machine_block WHERE id IN (SELECT value FROM json_each(?)))
                """, arguments: lines.arguments + StatementArguments([try Coding.json(blocks)]))
    }

    /// Empties the words of these blocks and the note of these proposals. A block keeps its kind, its cites, and the
    /// settings of a view; the words a model wrote for it go, titles and headings among them, because a model that read
    /// the lines can carry their words into any text it wrote. Each block is flagged `words_erased`.
    static func eraseMachineWords(blocks: [String], pageProposals: [Int64], in db: Database) throws {
        try emptyWords(ofBlocks: blocks, in: db)
        try db.execute(
            sql: "UPDATE page_proposal SET note = '' WHERE id IN (SELECT value FROM json_each(?))",
            arguments: [try Coding.json(pageProposals)])
    }

    static func emptyWords(ofBlocks blocks: [String], in db: Database) throws {
        for row in try Row.fetchAll(
            db, sql: "SELECT id, spec FROM machine_block WHERE id IN (SELECT value FROM json_each(?))",
            arguments: [try Coding.json(blocks)])
        {
            let block: MachineBlock = try row.json("spec")
            try db.execute(
                sql: "UPDATE machine_block SET spec = ?, words_erased = 1 WHERE id = ?",
                arguments: [try Coding.json(block.emptied), row["id"] as String])
        }
    }
}
