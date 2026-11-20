import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// A row the app could not write itself, planted with raw SQL: it passes the table's checks but not the Swift type.
struct BadRowTests {
    private func plantItem(in store: Store, run: RunID, fields: String) throws {
        try store.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
                        created_at) VALUES ('day.timeline', ?, '2026-09-21', '', 'screen', 1, 1, '2026-09-21T10:00:00Z',
                        '2026-09-21T10:05:00Z', ?, 'q', '2026-09-21T10:06:00Z')
                    """, arguments: [run, fields])
        }
    }

    @Test func anItemWithFieldsOfTheWrongShapeMakesTheQueryThrowAndIsNotSkipped() throws {
        let store = try makeStore()
        let run = try store.beginRun(task: "day.timeline", model: "m", prompt: "p", input: "x", kinds: [])
        try plantItem(in: store, run: run, fields: #"{"task":"ok"}"#)
        let day = try #require(WorkDay("2026-09-21"))
        #expect(try store.queries.items(of: "day.timeline", day: day, scope: "").count == 1)

        try plantItem(in: store, run: run, fields: #"{"task":1}"#)
        let error = #expect(throws: StoreError.self) {
            try store.queries.items(of: "day.timeline", day: day, scope: "")
        }
        guard case .unreadableRow(let table, let id, _) = try #require(error) else {
            Issue.record("expected unreadableRow, got \(String(describing: error))")
            return
        }
        #expect(table == "item")
        #expect(id == 2)
    }

    @Test func aProposalWhoseEvidenceIsNotAListOfIdsMakesTheQueryThrow() throws {
        let store = try makeStore()
        let run = try store.beginRun(task: "mochi", model: "m", prompt: "p", input: "x", kinds: [])
        try store.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO proposal(run_id, name, template, brief, why, evidence, created_at)
                    VALUES (?, 'n', 't', 'b', 'w', '["x"]', '2026-09-21T10:00:00Z')
                    """, arguments: [run])
        }
        #expect(throws: StoreError.self) { try store.queries.proposals() }
    }

    @Test func aDateThatIsNotIso8601MakesTheQueryThrow() throws {
        let store = try makeStore()
        try store.writer.write { db in
            try db.execute(
                sql:
                    "INSERT INTO activity(ts, kind, app, bundle_id, title) VALUES ('2026-13-45T99:99:99Z', 'window', 'a', 'b', 't')"
            )
        }
        #expect(throws: StoreError.self) { try store.queries.activities(since: .distantPast) }
    }
}
