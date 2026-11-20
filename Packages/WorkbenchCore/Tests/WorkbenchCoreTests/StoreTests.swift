import Foundation
import GRDB
import Synchronization
import Testing

@testable import WorkbenchCore

private func userVersion(in folder: URL) throws -> Int? {
    try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path).read { db in
        try Int.fetchOne(db, sql: "PRAGMA user_version")
    }
}

/// A store as the shipped app left it: the first `count` steps run, `user_version` set to `count`, some marks kept.
private func storeMade(withSteps count: Int, in folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
    try queue.write { db in
        for statement in Schema.steps.prefix(count).joined() { try db.execute(sql: statement) }
        try db.execute(sql: "PRAGMA user_version = \(count)")
        try db.execute(sql: "INSERT INTO state(key, value, saved_at) VALUES ('kept', 'yes', '2026-11-19T10:00:00Z')")
    }
}

private func mode(_ url: URL) throws -> Int {
    try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
}

struct SchemaTests {
    /// The digest of each shipped step. A shipped step never changes; a new step adds a line here. The first is the
    /// whole schema as of 2026-11-19 (checked equal, table by table, to the chain of steps it replaced).
    private let shipped = [
        "00fdbbe73d6e0a0a4a4a3d12e117d15fcc162b0d35f7458d557a70b8cb937137",
        "3e5bb4786866f0e70a7ffe1c95d129e977c00e587edbd8cbe841fa97f06b9e03",
        "32a1eedf0b89310a5670c882141c9d3615c12830ca1f5bfbce8bfc03e9d39de3",
        "722059e5e1489b0e7c25a4c6fae8d1be92b992326251609f3de804b0125b2349",
        "b902a94e25dfc277336f1f925e4e9034cc9bccb3b28216c2f7f74e1364632226",
    ]

    @Test func aShippedStepNeverChanges() {
        #expect(Array(Schema.stepDigests.prefix(shipped.count)) == shipped)
        #expect(Schema.stepDigests.count >= shipped.count)
    }

    @Test func aNewStoreIsAtTheLatestVersionAndKeepsItsDataWhenOpenedAgain() throws {
        let folder = temporaryDirectory()
        let store = try Store(directory: folder)
        try store.saveState("kept", forKey: "probe")
        #expect(try userVersion(in: folder) == Schema.steps.count)
        #expect(try Store(directory: folder).queries.state(forKey: "probe") == "kept")
    }

    @Test func aStoreAtAnEarlierVersionKeepsItsDataAndRunsOnlyTheMissingSteps() throws {
        let folder = temporaryDirectory()
        try storeMade(withSteps: 1, in: folder)
        let store = try Store(directory: folder)
        #expect(try store.queries.state(forKey: "kept") == "yes")
        #expect(try userVersion(in: folder) == Schema.steps.count)
        #expect(try store.writer.read { try Bool.fetchOne($0, sql: "SELECT COUNT(*) = 0 FROM item_event") } == true)
    }

    @Test func aStoreAtTheLatestVersionOpensUnchanged() throws {
        let folder = temporaryDirectory()
        try storeMade(withSteps: Schema.steps.count, in: folder)
        #expect(try Store(directory: folder).queries.state(forKey: "kept") == "yes")
    }

    @Test func aStoreFromANewerAppIsRefusedAndLeftAlone() throws {
        let folder = temporaryDirectory()
        try storeMade(withSteps: Schema.steps.count, in: folder)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        try queue.write { try $0.execute(sql: "PRAGMA user_version = \(Schema.steps.count + 1)") }
        #expect(throws: SchemaError.newerVersion) { try Store(directory: folder) }
        #expect(try userVersion(in: folder) == Schema.steps.count + 1)
    }

    @Test func storesOpeningTogetherRunEachStepOnce() throws {
        for _ in 0..<25 {
            let folder = temporaryDirectory()
            let outcomes = Mutex<[Result<Void, any Error>]>([])
            DispatchQueue.concurrentPerform(iterations: 4) { _ in
                let outcome = Result { _ = try Store(directory: folder) }
                outcomes.withLock { $0.append(outcome) }
            }
            for outcome in outcomes.withLock({ $0 }) { try outcome.get() }
            #expect(try userVersion(in: folder) == Schema.steps.count)
        }
    }

    @Test func theFolderIsOwnerOnlyAndAFolderMadeOpenIsClosedAgain() throws {
        let store = try makeStore()
        #expect(try mode(store.directory) == 0o700)
        #expect(try mode(store.directory.appending(path: "workbench.sqlite")) == 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.directory.path)
        #expect(try mode(store.reopened().directory) == 0o700)
    }
}

/// Step 3 rebuilds `item` while other tables point at it.
struct ItemRebuildTests {
    private let itemColumns = """
        task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote, created_at
        """

    /// A store at step 2 with a run, items 1 to 3, a mark and a close event on item 3, and a proposal citing item 3.
    private func storeAtStepTwo() throws -> URL {
        let folder = temporaryDirectory()
        try storeMade(withSteps: 2, in: folder)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                    VALUES ('t', 'm', 'p', 0, 's', '2026-11-19T10:00:00Z', '2026-11-19T10:00:01Z', 'done')
                    """)
            for number in 1...3 {
                try db.execute(
                    sql: """
                        INSERT INTO item(\(itemColumns)) VALUES ('t', 1, '2026-11-19', '', 'screen', 1, 1,
                            '2026-11-19T10:00:00Z', '2026-11-19T11:00:00Z', '{}', 'q\(number)', '2026-11-19T12:00:00Z')
                        """)
            }
            try db.execute(
                sql:
                    "INSERT INTO mark(item_id, ts, state, origin) VALUES (3, '2026-11-19T13:00:00Z', 'confirmed', 'voluntary')"
            )
            try db.execute(
                sql: """
                    INSERT INTO item_event(item_id, kind, outcome, valid_at, recorded_at, actor)
                    VALUES (3, 'close', 'done', '2026-11-19T13:00:00Z', '2026-11-19T13:00:00Z', 'person')
                    """)
            try db.execute(
                sql: """
                    INSERT INTO proposal(run_id, name, template, brief, why, evidence, created_at)
                    VALUES (1, 'n', 't', 'b', 'w', '[3]', '2026-11-19T14:00:00Z')
                    """)
        }
        return folder
    }

    @Test func theRebuildKeepsRowsMarksEventsViewsAndIndexes() throws {
        let store = try Store(directory: storeAtStepTwo())
        try store.writer.read { db in
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item") == 3)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mark") == 1)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_event") == 1)
            #expect(try String.fetchOne(db, sql: "SELECT state FROM item_mark WHERE id = 3") == "confirmed")
            #expect(try String.fetchOne(db, sql: "SELECT status_kind FROM item_status WHERE item_id = 3") == "close")
            #expect(try String.fetchAll(db, sql: "SELECT quote FROM item ORDER BY id") == ["q1", "q2", "q3"])
            let indexes = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'"))
            #expect(indexes.isSuperset(of: ["item_day", "item_run", "mark_item", "machine_change_machine"]))
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try Int.fetchOne(db, sql: "PRAGMA foreign_keys") == 1)
        }
    }

    @Test func aDeletedHighestItemIdIsNotGivenToTheNextItem() throws {
        let store = try Store(directory: storeAtStepTwo())
        try store.writer.write { db in
            try db.execute(sql: "DELETE FROM item WHERE id = 3")
            try db.execute(
                sql: """
                    INSERT INTO item(\(itemColumns)) VALUES ('t', 1, '2026-11-19', '', 'screen', 1, 1,
                        '2026-11-19T10:00:00Z', '2026-11-19T11:00:00Z', '{}', 'q4', '2026-11-19T12:00:00Z')
                    """)
            #expect(try Int.fetchOne(db, sql: "SELECT id FROM item WHERE quote = 'q4'") == 4)
        }
    }

    @Test func deletingAnItemStillRemovesItsMarksAndEvents() throws {
        let store = try Store(directory: storeAtStepTwo())
        try store.writer.write { db in
            try db.execute(sql: "DELETE FROM item WHERE id = 3")
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mark") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_event") == 0)
        }
    }

    @Test func aStepThatLeavesADanglingReferenceIsRefusedAndRolledBack() throws {
        let folder = try storeAtStepTwo()
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(sql: "DELETE FROM run")
        }
        #expect(throws: DatabaseError.self) { try Store(directory: folder) }
        #expect(try userVersion(in: folder) == 2)
    }
}

private struct Reply: Decodable, Sendable {
    var answer: String
}

private let replySchema = JSONSchema.object([.init("answer", .string)])

struct RunTests {
    @Test func aCallIsARunWithItsUsageAndAFailedCallIsAFailedRun() async throws {
        let store = try makeStore()
        let done = RecordedModel(ScriptedModel(#"{"answer":"yes"}"#), store: store)
        let (value, id) = try await done.generate(
            Reply.self, schema: replySchema, task: "test", instructions: "be brief", input: "hello",
            holding: [])
        #expect(value.answer == "yes")

        let failing = RecordedModel(ScriptedModel(failing: .unavailable("limit")), store: store)
        await #expect(throws: StructuredModelError.unavailable("limit")) {
            try await failing.generate(
                Reply.self, schema: replySchema, task: "test", instructions: "be brief", input: "hello",
                holding: [])
        }

        let runs = try store.queries.runs()
        #expect(runs.map(\.outcome) == [.failed, .done])
        let run = try #require(runs.last)
        #expect(run.id == id)
        #expect(run.model == "scripted-1")
        #expect(run.inputBytes == 5)
        #expect(run.usage == Usage(inputTokens: 100, outputTokens: 20, costUSD: 0.01))
        #expect(runs.first?.model == "scripted")
        #expect(runs.first?.error != nil)
        #expect(try store.queries.usage(since: t0).tokens == 120)
        #expect(try store.queries.usage(since: day(1)).tokens == 0)
    }

}
