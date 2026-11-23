import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// The fact lifecycle step rebuilds `item_event` while a store holds events written the old way, and a dry run counts
/// what it changes on a copy.
@Suite struct FactLifecycleStepTests {
    private static let day3 = "2026-11-20T10:00:00Z"
    private static let day4 = "2026-11-21T10:00:00Z"
    private static let day5 = "2026-11-22T10:00:00Z"

    /// A store one step before the last, with six items and seven events:
    /// 1 a model close; 2 a person close; 3 a person close (valid day 4) and then a reopen recorded later but valid
    /// earlier (day 3); 4 a model close and a person reopen; 5 a model reopen; 6 a typed fact with no event.
    private func storeBeforeTheStep() throws -> URL {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        try queue.write { db in
            let before = Schema.steps.firstIndex(of: Schema.factLifecycle)!
            for statement in Schema.steps.prefix(before).joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = \(before)")
            try db.execute(
                sql: """
                    INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                    VALUES ('t', 'm', 'p', 0, 's', '2026-11-19T10:00:00Z', '2026-11-19T10:00:01Z', 'done')
                    """)
            for number in 1...5 {
                try db.execute(
                    sql: """
                        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at,
                            fields, quote, created_at) VALUES ('t', 1, '2026-11-19', '', 'whatsapp', \(number + 10),
                            \(number + 10), '2026-11-19T10:00:00Z', '2026-11-19T11:00:00Z', '{"kind":"plan"}',
                            'q\(number)', '2026-11-19T12:00:00Z')
                        """)
            }
            try db.execute(
                sql: """
                    INSERT INTO item(task, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
                        created_at) VALUES ('t', '2026-11-19', '', 'typed', 0, 0, '2026-11-19T10:00:00Z',
                        '2026-11-19T11:00:00Z', '{}', 'typed', '2026-11-19T12:00:00Z')
                    """)
            let columns =
                "INSERT INTO item_event(item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor)"
            for (item, kind, at) in [(1, "close", Self.day3), (4, "close", Self.day3)] {
                try db.execute(
                    sql: "\(columns) VALUES (?, ?, 'kept', 7, 'said', ?, ?, 1, 'model')",
                    arguments: [item, kind, at, at])
            }
            for (item, kind, at) in [(2, "close", Self.day3), (3, "close", Self.day4)] {
                try db.execute(
                    sql: "\(columns) VALUES (?, ?, 'kept', NULL, NULL, ?, ?, NULL, 'person')",
                    arguments: [item, kind, at, at])
            }
            try db.execute(
                sql: "\(columns) VALUES (3, 'reopen', NULL, NULL, NULL, ?, ?, NULL, 'person')",
                arguments: [Self.day3, Self.day5])
            try db.execute(
                sql: "\(columns) VALUES (4, 'reopen', NULL, NULL, NULL, ?, ?, NULL, 'person')",
                arguments: [Self.day4, Self.day4])
            try db.execute(
                sql: "\(columns) VALUES (5, 'reopen', NULL, 7, 'again', ?, ?, 1, 'model')",
                arguments: [Self.day4, Self.day4])
        }
        return folder
    }

    @Test func theStepRebuildsEveryEventKeepingIdsAndLinesAndAddsOneOpenPerItem() throws {
        let store = try Store(directory: storeBeforeTheStep())
        let (count, ids, lines, dangling) = try store.writer.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_event"),
                try Int64.fetchAll(db, sql: "SELECT id FROM item ORDER BY id"),
                try Row.fetchAll(db, sql: "SELECT id, line_id FROM item_event WHERE id <= 7 ORDER BY id")
                    .map { [$0["id"] as Int64, ($0["line_id"] as Int64?) ?? -1] },
                try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            )
        }
        #expect(count == 7 + 6, "the old events and one open event for each of the six items")
        #expect(ids == [1, 2, 3, 4, 5, 6] && dangling.isEmpty)
        #expect(
            lines == [[1, 7], [2, 7], [3, -1], [4, -1], [5, -1], [6, -1], [7, 7]], "no line_id is rewritten")
    }

    @Test func aModelCloseBecomesAProposalAndAModelReopenBecomesAFlag() throws {
        let store = try Store(directory: storeBeforeTheStep())
        let rows = try store.writer.read { db in
            try Row.fetchAll(
                db, sql: "SELECT id, kind, outcome FROM item_event WHERE actor = 'model' AND id <= 7 ORDER BY id")
        }
        #expect(rows.map { $0["kind"] as String } == ["close_proposed", "close_proposed", "flag"])
        #expect(rows.map { $0["outcome"] as String? } == ["kept", "kept", nil])
    }

    @Test func theLogListsEachItemWhoseStatusChangesWithItsReason() throws {
        let store = try Store(directory: storeBeforeTheStep())
        let log = try store.queries.lifecycleRebuild()
        #expect(log.items == 6 && log.eventsBefore == 7)
        #expect(
            log.changes == [
                .init(item: 1, was: "closed", now: "open", reason: "model_close_became_a_proposal"),
                .init(item: 3, was: "open", now: "closed", reason: "valid_time_order"),
            ])
        #expect(log.byReason == ["model_close_became_a_proposal": 1, "valid_time_order": 1])
    }

    @Test func statusAfterTheStepFollowsValidTimeAndAProposalIsPendingOnlyWhenNobodyActedSince() throws {
        let store = try Store(directory: storeBeforeTheStep())
        let items = try store.queries.items(of: "t", since: #require(WorkDay("2026-11-19")))
        #expect(items.map { $0.closed?.outcome } == [nil, "kept", "kept", nil, nil, nil])
        #expect(try store.queries.closeProposals(of: "t").map(\.id) == [1])
        #expect(items[0].proposedClose?.outcome == "kept" && items[3].proposedClose == nil)
    }

    @Test func theDryRunCountsOnACopyAndLeavesTheStoreAtItsOldVersion() throws {
        let folder = try storeBeforeTheStep()
        let report = try LifecycleDryRun.run(onCopyOf: folder)
        #expect(report.items == 6 && report.eventsBefore == 7 && report.changes.count == 2)
        #expect(report.byReason == ["model_close_became_a_proposal": 1, "valid_time_order": 1])
        let version = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path).read {
            try Int.fetchOne($0, sql: "PRAGMA user_version")
        }
        #expect(
            version == Schema.steps.firstIndex(of: Schema.factLifecycle)!, "the store the dry run read is not migrated")
        let store = try Store(directory: folder)
        #expect(try store.queries.lifecycleRebuild() == report, "the real step logs what the dry run said")
    }

    @Test func aStoreWithNoChangesReportsNone() throws {
        let store = try makeStore()
        #expect(try store.queries.lifecycleRebuild() == LifecycleDryRun(items: 0, eventsBefore: 0, changes: []))
    }
}
