import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// Step 7 lets a typed fact have no run, and moves the old deal actions, which a fake run stood for, to the kind `typed`.
@Suite struct TypedItemsStepTests {
    private func storeAtStepSix() throws -> URL {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        try queue.write { db in
            for statement in Schema.steps.prefix(6).joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = 6")
            for (task, model) in [("vc.deals-1", "m"), ("vc.deal-actions", "you"), ("vc.deal-actions", "you")] {
                try db.execute(
                    sql: """
                        INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                        VALUES (?, ?, 'p', 0, 's', '2026-11-19T10:00:00Z', '2026-11-19T10:00:01Z', 'done')
                        """, arguments: [task, model])
            }
            for (run, task) in [(1, "vc.deals-1"), (2, "vc.deal-actions"), (3, "vc.deal-actions")] {
                try db.execute(
                    sql: """
                        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at,
                            fields, quote, created_at) VALUES (?, ?, '2026-11-19', '', 'screen_text', 0, 0,
                            '2026-11-19T10:00:00Z', '2026-11-19T10:00:00Z', '{}', 'q', '2026-11-19T12:00:00Z')
                        """, arguments: [task, run])
            }
            try db.execute(
                sql: """
                    INSERT INTO mark(item_id, ts, state, origin) VALUES (1, '2026-11-19T13:00:00Z', 'confirmed', 'voluntary')
                    """)
            try db.execute(
                sql: """
                    INSERT INTO item_event(item_id, kind, outcome, valid_at, recorded_at, actor)
                    VALUES (2, 'close', 'done', '2026-11-19T14:00:00Z', '2026-11-19T14:00:00Z', 'person')
                    """)
        }
        return folder
    }

    @Test func oldDealActionsBecomeTypedAndLoseTheirFakeRunWhileOtherItemsStay() throws {
        let store = try Store(directory: storeAtStepSix())
        let (items, runs, marks, events, dangling) = try store.writer.read { db in
            (
                try Row.fetchAll(db, sql: "SELECT id, source, run_id FROM item ORDER BY id").map {
                    "\($0["id"] as Int64) \($0["source"] as String) \($0["run_id"] as Int64? ?? 0)"
                },
                try String.fetchAll(db, sql: "SELECT task FROM run"),
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_mark WHERE state = 'confirmed'"),
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_status WHERE status_kind = 'close'"),
                try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            )
        }
        #expect(items == ["1 screen_text 1", "2 typed 0", "3 typed 0"])
        #expect(runs == ["vc.deals-1"] && marks == 1 && events == 1 && dangling.isEmpty)
        let actions = try store.queries.dealActions()
        #expect(actions.map(\.source) == [.typed, .typed] && actions[0].closed?.outcome == "done")
    }

    @Test func theRebuildKeepsTheIndexesAndTheViews() throws {
        let store = try Store(directory: storeAtStepSix())
        let names = try store.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE tbl_name = 'item' OR name = 'item_mark'")
        }
        #expect(Set(names) == ["item", "item_day", "item_run", "item_mark"])
    }
}
