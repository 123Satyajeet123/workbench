import Foundation
import GRDB

extension Store {
    /// Empties the words of every block of a machine that rests on one of the lines, or on one of the facts the same
    /// erase flagged, whatever the state of the block (proposed, live, replaced or removed), and the note of each
    /// proposal those blocks came from or that asked with one of the lines. A block keeps its kind, its cites, and the
    /// settings of a view; the words a model wrote for it go, titles and headings among them, because a model that read
    /// the lines can carry their words into any text it wrote. Each block is flagged `words_erased`.
    static func eraseMachineWords(citing lines: LineSelection, orFacts facts: String, in db: Database) throws {
        let blocks = try String.fetchAll(
            db,
            sql: """
                SELECT DISTINCT block_id FROM machine_block_cite
                WHERE line_id IN (\(lines.sql)) OR item_id IN (SELECT value FROM json_each(?))
                """, arguments: lines.arguments + StatementArguments([facts]))
        try emptyWords(ofBlocks: blocks, in: db)
        try db.execute(
            sql: """
                UPDATE page_proposal SET note = ''
                WHERE request_line IN (\(lines.sql)) OR id IN (
                    SELECT proposal_id FROM machine_block WHERE id IN (SELECT value FROM json_each(?)))
                """, arguments: lines.arguments + StatementArguments([try Coding.json(blocks)]))
    }

    private static func emptyWords(ofBlocks blocks: [String], in db: Database) throws {
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
