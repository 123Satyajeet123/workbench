import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// Step 5 rebuilds `item_event` while a store holds events from step 2.
@Suite struct ItemActionsStepTests {
    private func storeAtStepFour() throws -> URL {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        try queue.write { db in
            for statement in Schema.steps.prefix(4).joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = 4")
            try db.execute(
                sql: """
                    INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                    VALUES ('t', 'm', 'p', 0, 's', '2026-11-19T10:00:00Z', '2026-11-19T10:00:01Z', 'done')
                    """)
            for number in 1...2 {
                try db.execute(
                    sql: """
                        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at,
                            fields, quote, created_at) VALUES ('t', 1, '2026-11-19', '', 'whatsapp', 1, 1,
                            '2026-11-19T10:00:00Z', '2026-11-19T11:00:00Z', '{}', 'q\(number)', '2026-11-19T12:00:00Z')
                        """)
            }
            try db.execute(
                sql: """
                    INSERT INTO item_event(item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor)
                    VALUES (1, 'close', 'kept', 5, 'done', '2026-11-19T13:00:00Z', '2026-11-19T13:00:00Z', 1, 'model')
                    """)
            try db.execute(
                sql: """
                    INSERT INTO item_event(item_id, kind, valid_at, recorded_at, actor)
                    VALUES (1, 'reopen', '2026-11-19T14:00:00Z', '2026-11-19T14:00:00Z', 'person')
                    """)
        }
        return folder
    }

    @Test func aStoreAtStepFourKeepsItsEventsAndTheirStatusAndTakesActions() throws {
        let store = try Store(directory: storeAtStepFour())
        let (events, status, closer, dangling) = try store.writer.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_event"),
                try String.fetchOne(db, sql: "SELECT status_kind FROM item_status WHERE item_id = 1"),
                try String.fetchOne(db, sql: "SELECT actor FROM item_event WHERE kind = 'close'"),
                try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            )
        }
        #expect(events == 2 && status == "reopen" && closer == "model" && dangling.isEmpty)
        try store.apply(.snooze(until: WorkDay(containing: t0)), to: [1])
        try store.apply(.done(outcome: "kept"), to: [2])
        let items = try store.queries.items(of: "t", since: #require(WorkDay("2026-11-19")))
        #expect(items[0].closed == nil && items[0].hiding != nil)
        #expect(items[1].closed?.outcome == "kept" && items[1].hiding == nil)
    }
}
