import Foundation
import GRDB
import Kernel
import Testing

@testable import WorkbenchCore

/// The step that marks a line whose words were quoted or forwarded: a column that is 0 or 1 and never changes.
@Suite struct EvidenceForwardedStepTests {
    private func storeBeforeTheStep() throws -> URL {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        let before = Schema.steps.prefix(while: { $0 != Schema.evidenceForwarded })
        try queue.write { db in
            for statement in before.joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = \(before.count)")
            try db.execute(
                sql: """
                    INSERT INTO evidence(line_id, entity_key, quality, source_id, container, event_time, first_seen,
                        last_seen, actor, text, tombstone, label_id, grant_id, audience_digest, retention_class,
                        obtained_by, reader_version) VALUES (?, x'01', 'stable', ?, 'c', 1, 1, 1, 'a', 'old words', 0, ?,
                        'mail:Deals', ?, 'mail', 'dom_text', 'v')
                    """,
                arguments: [
                    Data(repeating: 1, count: 32), Data(repeating: 2, count: 16), Data(repeating: 3, count: 16),
                    Data(repeating: 4, count: 32),
                ])
        }
        return folder
    }

    @Test func anEarlierStoreKeepsItsLinesAndTheyAreNotForwarded() throws {
        let store = try Store(directory: storeBeforeTheStep())
        let line = try store.writer.read { try Row.fetchOne($0, sql: "SELECT text, forwarded FROM evidence") }
        #expect(line?["text"] == "old words" && line?["forwarded"] == 0)
    }

    @Test func theMarkIsZeroOrOneAndNeverChanges() throws {
        let store = try Store(directory: storeBeforeTheStep())
        #expect(throws: (any Error).self) {
            try store.writer.write { try $0.execute(sql: "UPDATE evidence SET forwarded = 1") }
        }
        #expect(throws: (any Error).self) {
            try store.writer.write { try $0.execute(sql: "UPDATE evidence SET forwarded = 2") }
        }
        #expect(throws: (any Error).self) {
            try store.writer.write { try $0.execute(sql: "UPDATE evidence SET text = 'changed'") }
        }
        let line = try store.writer.read { try Row.fetchOne($0, sql: "SELECT text, forwarded FROM evidence") }
        #expect(line?["text"] == "old words" && line?["forwarded"] == 0)
        #expect(throws: (any Error).self) {
            try store.writer.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO evidence(line_id, entity_key, quality, source_id, container, first_seen, last_seen,
                            text, tombstone, label_id, grant_id, audience_digest, retention_class, obtained_by,
                            reader_version, forwarded) VALUES (?, x'02', 'stable', ?, 'c', 1, 1, 'w', 0, ?, 'g', ?,
                            'mail', 'dom_text', 'v', 2)
                        """,
                    arguments: [
                        Data(repeating: 9, count: 32), Data(repeating: 2, count: 16), Data(repeating: 3, count: 16),
                        Data(repeating: 4, count: 32),
                    ])
            }
        }
    }
}
