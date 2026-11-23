import Foundation
import GRDB
import Kernel
import Lines

/// Where a quoted paragraph went: it was joined to another one, and its words live on there.
public struct ParagraphMove: Equatable, Sendable {
    public static let words = "Moved into another paragraph"

    public var note: NoteID
    /// The block that holds the words now.
    public var into: BlockID
}

extension Store {
    /// Saves what the editor changed in one note, in one transaction with the person's consent: the lines of the blocks
    /// that are new or changed, the endings, and the order. An edited block is a new version of its line; the old
    /// version stays as an earlier one. A deleted block erases every version and every copy. A merged block erases
    /// nothing. Blocks the store refused, because their names ended, are in the report as `refusedAfterRevoke`.
    @discardableResult
    public func saveNote(_ change: NoteChange, owner: PersonID) async throws -> IngestReport {
        try await write(.save(change), owner: owner)
    }

    /// Deletes a note: a tombstone for each of its blocks, so no version of any paragraph is left.
    @discardableResult
    public func deleteNote(_ note: NoteID, owner: PersonID) async throws -> IngestReport {
        try await write(.erase(note), owner: owner)
    }

    /// A write that failed leaves nothing in the store and is thrown, not reported: the editor keeps the change.
    private func write(_ work: NoteSource.Work, owner: PersonID) async throws -> IngestReport {
        let report = try await ingest(NoteSource(store: self, work: work), owner: owner, now: clock())
        if let failure = report.failures.first { throw failure.error }
        return report
    }
}

extension Queries {
    /// The paragraphs of a note in order, each with its words as they are now.
    public func noteBlocks(of note: NoteID) throws -> [NoteBlock] {
        try reader.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.message_ref AS block, e.text FROM container_order o
                    JOIN evidence e ON e.entity_key = o.entity_key AND e.id = (
                        SELECT v.id FROM evidence v WHERE v.entity_key = o.entity_key AND v.tombstone = 0
                        ORDER BY v.last_seen DESC, v.id DESC LIMIT 1)
                    WHERE o.container = ? ORDER BY o.position
                    """, arguments: [note.rawValue]
            ).compactMap { row in BlockID(row["block"]).map { NoteBlock(id: $0, text: row["text"]) } }
        }
    }

    /// Where the words of a cited line went, when its paragraph was joined to another one; nil otherwise.
    public func paragraphMove(ofLine lineID: Data) throws -> ParagraphMove? {
        try reader.read { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        WITH RECURSIVE chain(entity, depth) AS (
                            SELECT s.into_key, 1 FROM evidence e JOIN entity_supersede s ON s.entity_key = e.entity_key
                            WHERE e.line_id = ?
                            UNION SELECT s.into_key, chain.depth + 1 FROM chain
                            JOIN entity_supersede s ON s.entity_key = chain.entity)
                        SELECT e.container, e.message_ref FROM chain JOIN evidence e ON e.entity_key = chain.entity
                        WHERE e.message_ref IS NOT NULL ORDER BY chain.depth DESC, e.id DESC LIMIT 1
                        """, arguments: [lineID]),
                let note = NoteID(project: row["container"]), let into = BlockID(row["message_ref"])
            else { return nil }
            return ParagraphMove(note: note, into: into)
        }
    }

    /// Every block of a note that has words in the store.
    func blocks(of note: NoteID) throws -> [BlockID] {
        try reader.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT message_ref FROM evidence WHERE container = ? AND tombstone = 0
                        AND message_ref IS NOT NULL AND grant_id = ?
                    """, arguments: [note.rawValue, Store.grantID(kind: .note, label: note.rawValue)]
            ).compactMap(BlockID.init)
        }
    }

    /// `block` and every block whose words were joined into it, and into those.
    func blocks(joinedInto block: BlockID, of note: NoteID) throws -> [BlockID] {
        let key = Data(try EntityKey.block(block, of: note).bytes)
        return try reader.read { db in
            try String.fetchAll(
                db,
                sql: """
                    WITH RECURSIVE joined(entity) AS (
                        SELECT ? UNION SELECT s.entity_key FROM entity_supersede s JOIN joined ON s.into_key = joined.entity)
                    SELECT DISTINCT message_ref FROM evidence WHERE container = ? AND message_ref IS NOT NULL
                        AND entity_key IN (SELECT entity FROM joined)
                    """, arguments: [key, note.rawValue]
            ).compactMap(BlockID.init) + [block]
        }
    }
}
