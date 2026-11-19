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

private struct Reply: Decodable, Sendable {
    var answer: String
}

private let replySchema = JSONSchema.object([.init("answer", .string)])

struct RunTests {
    @Test func aCallIsARunWithItsUsageAndAFailedCallIsAFailedRun() async throws {
        let store = try makeStore()
        let done = RecordedModel(ScriptedModel(#"{"answer":"yes"}"#), store: store)
        let (value, id) = try await done.generate(
            Reply.self, schema: replySchema, task: "test", instructions: "be brief", input: "hello")
        #expect(value.answer == "yes")

        let failing = RecordedModel(ScriptedModel(failing: .unavailable("limit")), store: store)
        await #expect(throws: StructuredModelError.unavailable("limit")) {
            try await failing.generate(
                Reply.self, schema: replySchema, task: "test", instructions: "be brief", input: "hello")
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
