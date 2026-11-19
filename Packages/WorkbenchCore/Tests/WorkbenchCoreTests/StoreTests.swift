import Foundation
import Testing

@testable import WorkbenchCore

private func userVersion(in folder: URL) throws -> Int64? {
    try Database(path: folder.appending(path: "workbench.sqlite").path).rows("PRAGMA user_version").first?.first?
        .integer
}

private func setUserVersion(_ version: Int32, in folder: URL) throws {
    try Database(path: folder.appending(path: "workbench.sqlite").path).run("PRAGMA user_version = \(version)")
}

private func mode(_ url: URL) throws -> Int {
    try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
}

struct SchemaTests {
    /// The digest of each shipped step. A shipped step never changes; a new step adds a line here.
    private let shipped = [
        "dc7fb56e82933109fc9d23e8f416cef704a7442c446deb45c4779f39fce7a7a5",
        "d5f3a25c3985b819a4dba11053332e828911467e850086d34be39652a062e927",
        "b08e6b2a7bb7f102beeb8ce85674463fb1bfc3871c0496810997c4d8dbdea6ba",
        "a6a9d2a81a24b147d2f2fa8fde1016a72e2044fba57648a92387e9b5776c769c",
        "ec020f3c73ae5d70c0f8ad4332b4c567326f409cd42cd85671852454291d29e8",
    ]

    @Test func aNewStoreRunsEveryStepAndIsStampedWithTheirCount() throws {
        let store = try makeStore()
        let tables = try store.database.rows("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
            .compactMap { $0[0].string }
        #expect(
            tables == ["activity", "consent", "item", "mark", "prompt", "recording", "run", "state"])
        #expect(Set(Queries.Table.allCases.map(\.rawValue)) == Set(tables))
        #expect(try userVersion(in: store.directory) == Int64(Schema.steps.count))
        _ = try store.reopened()
    }

    @Test func aShippedStepNeverChanges() {
        #expect(Array(Schema.stepDigests.prefix(shipped.count)) == shipped)
        #expect(Schema.stepDigests.count >= shipped.count)
    }

    @Test func anOlderStoreGetsTheMissingStepsAndItsLedgerBecomesItemsWithTheirMarks() throws {
        let folder = temporaryDirectory()
        let store = try Store(directory: folder)
        try store.saveState("kept", forKey: "probe")
        try store.database.run("DROP VIEW item_mark")
        for table in ["mark", "item", "prompt"] { try store.database.run("DROP TABLE \(table)") }
        for statement in Schema.steps[0] { try store.database.run(statement) }
        let run = try store.beginRun(task: "team.ledger", model: "m", prompt: "p", input: "x")
        for (message, state) in [(11, "confirmed"), (12, "proposed")] {
            try store.database.run(
                """
                INSERT INTO ledger_entry(run_id, chat, day, person, kind, text, eta, quote, message_id, said_at, state,
                    created_at) VALUES (?, 'team', '2026-09-21', 'Asha', 'done', 'Login', '', 'login done', ?,
                    '2026-09-21T15:00:00Z', ?, '2026-09-21T16:00:00Z')
                """, [.int(run), .int(Int64(message)), .text(state)])
        }
        try setUserVersion(1, in: folder)
        let upgraded = try Store(directory: folder)
        #expect(try userVersion(in: folder) == Int64(Schema.steps.count))
        #expect(try upgraded.queries.state(forKey: "probe") == "kept")
        let items = try upgraded.queries.items(
            of: "team.ledger", day: try #require(WorkDay("2026-09-21")), scope: "team")
        #expect(items.map(\.citeFirst) == [11, 12])
        #expect(items.map(\.state) == [.confirmed, .proposed])
        #expect(items.first?["person"] == "Asha")
        #expect(try upgraded.queries.count(of: .mark) == 1)
    }

    @Test func aStoreFromANewerVersionIsRefusedAndAnUnstampedOneIsStamped() throws {
        let folder = temporaryDirectory()
        _ = try Store(directory: folder)
        try setUserVersion(Schema.version + 1, in: folder)
        #expect(throws: SchemaError.newerVersion) { try Store(directory: folder) }
        try setUserVersion(Schema.version, in: folder)
        _ = try Store(directory: folder)
        let fresh = temporaryDirectory()
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        try setUserVersion(0, in: fresh)
        _ = try Store(directory: fresh)
        #expect(try userVersion(in: fresh) == Int64(Schema.version))
    }

    @Test func theFolderIsOwnerOnlyAndAFolderMadeOpenIsClosedAgain() throws {
        let store = try makeStore()
        #expect(try mode(store.directory) == 0o700)
        #expect(try mode(store.directory.appending(path: "workbench.sqlite")) == 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.directory.path)
        #expect(try mode(store.reopened().directory) == 0o700)
    }
}

struct StateTests {
    @Test func aKeyHoldsTheLastValueSavedAndAnUnknownKeyHoldsNone() throws {
        let store = try makeStore()
        #expect(try store.queries.state(forKey: "a") == nil)
        try store.saveState("one", forKey: "a")
        try store.saveState("two", forKey: "a")
        try store.saveState("other", forKey: "b")
        #expect(try store.queries.state(forKey: "a") == "two")
        #expect(try store.queries.state(forKey: "b") == "other")
    }

    @Test func theLatestConsentIsThePolicyAndANewStoreHasTheDefault() throws {
        let store = try makeStore()
        #expect(try store.queries.policy() == CapturePolicy())
        try store.savePolicy(CapturePolicy(switches: [.screen: true]))
        try store.savePolicy(CapturePolicy(switches: [.files: true]))
        #expect(try store.queries.policy() == CapturePolicy(switches: [.files: true]))
        #expect(try store.queries.count(of: .consent) == 2)
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

    @Test func thePromptVersionChangesWithTheInstructionsAndNotWithTheInput() async throws {
        let store = try makeStore()
        let model = RecordedModel(ScriptedModel(#"{"answer":"yes"}"#), store: store)
        _ = try await model.generate(Reply.self, schema: replySchema, task: "test", instructions: "one", input: "a")
        _ = try await model.generate(Reply.self, schema: replySchema, task: "test", instructions: "one", input: "b")
        _ = try await model.generate(Reply.self, schema: replySchema, task: "test", instructions: "two", input: "a")
        let prompts = try store.queries.runs().map(\.prompt)
        #expect(prompts[1] == prompts[2])
        #expect(prompts[0] != prompts[1])
    }

    @Test func aRunLeftOpenIsClosedAsFailedAndAClosedRunStays() throws {
        let store = try makeStore()
        let open = try store.beginRun(task: "test", model: "m", prompt: "p", input: "x")
        let closed = try store.beginRun(task: "test", model: "m", prompt: "p", input: "x")
        try store.finishRun(closed, model: "m", usage: Usage(), error: nil)
        try store.closeInterruptedRuns()
        let outcomes = Dictionary(uniqueKeysWithValues: try store.queries.runs().map { ($0.id, $0.outcome) })
        #expect(outcomes == [open: .failed, closed: .done])
    }

    @Test func theSchemaRefusesARunWithoutATaskAndAFailureWithoutAReason() throws {
        let store = try makeStore()
        #expect(throws: (any Error).self) { try store.beginRun(task: "", model: "m", prompt: "p", input: "x") }
        let id = try store.beginRun(task: "test", model: "m", prompt: "p", input: "x")
        #expect(throws: (any Error).self) {
            try store.database.run("UPDATE run SET outcome = 'failed', ended_at = 'x' WHERE id = ?", [.int(id)])
        }
    }
}
