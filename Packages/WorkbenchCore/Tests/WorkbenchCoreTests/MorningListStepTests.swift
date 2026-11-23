import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// The morning list step rebuilds `item_event` while a store holds events and timers written the old way.
@Suite struct MorningListStepTests {
    /// A store one step before the last: one item with its open event, a person's close and snooze, and a timer
    /// armed by the open event.
    private func storeBeforeTheStep() throws -> URL {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        try queue.write { db in
            let before = Schema.steps.firstIndex(of: Schema.morningList)!
            for statement in Schema.steps.prefix(before).joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = \(before)")
            try db.execute(
                sql: """
                    INSERT INTO item(task, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
                        created_at) VALUES ('t', '2026-11-19', '', 'typed', 0, 0, '2026-11-19T10:00:00Z',
                        '2026-11-19T11:00:00Z', '{}', 'typed', '2026-11-19T12:00:00Z')
                    """)
            for (kind, outcome, until) in [("close", "kept", nil), ("snooze", nil, "2026-11-25T05:00:00Z")] {
                try db.execute(
                    sql: """
                        INSERT INTO item_event(item_id, kind, outcome, valid_at, recorded_at, actor, until)
                        VALUES (1, ?, ?, '2026-11-20T10:00:00Z', '2026-11-20T10:00:00Z', 'person', ?)
                        """, arguments: [kind, outcome, until])
            }
            try db.execute(
                sql: """
                    INSERT INTO timer(item_id, kind, fire_at, due_zone, due_source, precision, armed_by_event)
                    VALUES (1, 'due', '2026-11-21T10:00:00Z', 'UTC', 'stated', 'day', 1)
                    """)
        }
        return folder
    }

    @Test func theStepKeepsEveryEventAndTimerAndLeavesTheirSurfaceUnknown() throws {
        let store = try Store(directory: storeBeforeTheStep())
        let (events, timers, dangling) = try store.writer.read { db in
            (
                try Row.fetchAll(db, sql: "SELECT id, kind, actor, surface FROM item_event ORDER BY id"),
                try Row.fetchAll(db, sql: "SELECT armed_by_event FROM timer"),
                try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            )
        }
        #expect(events.map { $0["kind"] as String } == ["open", "close", "snooze"])
        #expect(events.allSatisfy { ($0["surface"] as String?) == nil }, "an old mark has no surface to name")
        #expect(timers.map { $0["armed_by_event"] as Int64 } == [1] && dangling.isEmpty)
    }

    @Test func theViewsStillReadTheOldEventsAndTheNewTriggersHold() throws {
        let store = try Store(directory: storeBeforeTheStep())
        let since = try #require(WorkDay("2026-11-19"))
        let item = try #require(store.queries.items(of: "t", since: since).first)
        let snoozedUntil = try Date("2026-11-25T05:00:00Z", strategy: .iso8601)
        #expect(item.closed?.outcome == "kept")
        #expect(item.hiding == .snoozed(until: snoozedUntil))
        #expect(throws: DatabaseError.self) {
            try store.writer.write {
                try $0.execute(
                    sql: """
                        INSERT INTO item_event(item_id, kind, valid_at, recorded_at, actor)
                        VALUES (1, 'unhide', '2026-11-21T10:00:00Z', '2026-11-21T10:00:00Z', 'person')
                        """)
            }
        }
        try store.reopen(item: 1, surface: .today)
        #expect(try store.queries.items(of: "t", since: since).first?.closed == nil)
    }
}
