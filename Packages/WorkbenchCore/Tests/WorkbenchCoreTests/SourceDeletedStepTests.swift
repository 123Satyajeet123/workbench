import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// The step that lets an item lose its quote when its source message is deleted.
@Suite struct SourceDeletedStepTests {
    private func storeBeforeTheStep() throws -> URL {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        let before = Schema.steps.prefix(while: { $0 != Schema.sourceDeleted })
        try queue.write { db in
            for statement in before.joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = \(before.count)")
            try db.execute(
                sql: """
                    INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                    VALUES ('t', 'm', 'p', 0, 's', '2026-11-19T10:00:00Z', '2026-11-19T10:00:01Z', 'done')
                    """)
            try db.execute(
                sql: """
                    INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                        quote, created_at) VALUES ('t', 1, '2026-11-19', '', 'whatsapp', 3, 4, '2026-11-19T10:00:00Z',
                        '2026-11-19T10:00:00Z', '{}', 'kept words', '2026-11-19T12:00:00Z')
                    """)
            try db.execute(
                sql:
                    "INSERT INTO mark(item_id, ts, state, origin) VALUES (1, '2026-11-19T13:00:00Z', 'confirmed', 'voluntary')"
            )
        }
        return folder
    }

    @Test func anEarlierStoreKeepsItsItemsAndMarksAndGainsTheFlagOff() throws {
        let store = try Store(directory: storeBeforeTheStep())
        let (row, dangling) = try store.writer.read { db in
            (
                try Row.fetchOne(db, sql: "SELECT quote, source_deleted, state, cite_first, cite_last FROM item_mark"),
                try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            )
        }
        #expect(row?["quote"] == "kept words" && row?["source_deleted"] == 0 && row?["state"] == "confirmed")
        #expect(row?["cite_first"] == 3 && row?["cite_last"] == 4 && dangling.isEmpty)
    }

    @Test func aQuoteIsEmptyExactlyWhenTheSourceIsFlaggedDeleted() throws {
        let store = try Store(directory: storeBeforeTheStep())
        func update(_ set: String) throws {
            try store.writer.write { try $0.execute(sql: "UPDATE item SET \(set)") }
        }
        #expect(throws: (any Error).self) { try update("quote = ''") }
        #expect(throws: (any Error).self) { try update("source_deleted = 1") }
        try update("quote = '', source_deleted = 1")
        #expect(throws: (any Error).self) { try update("quote = 'back'") }
    }
}
