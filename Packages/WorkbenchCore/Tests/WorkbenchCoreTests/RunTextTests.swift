import Foundation
import GRDB
import Synchronization
import Testing

@testable import WorkbenchCore

private let schema = JSONSchema.object([.init("items", .array(.string))])

/// A clock the test moves.
private final class MovingClock: Sendable {
    private let date = Mutex(t0)
    var current: Date { date.withLock { $0 } }
    func move(to newDate: Date) { date.withLock { $0 = newDate } }
}

/// A store on a moving clock, and a way to start a run at a chosen time.
private final class Timeline: Sendable {
    let clock = MovingClock()
    let store: Store

    init() throws {
        let clock = clock
        store = try makeStore(clock: { clock.current })
    }

    @discardableResult
    func run(
        _ kinds: Set<SourceKind>, unknown: Bool = false, task: String = "t", daysAgo: Double = 0, input: String = "in"
    ) async throws -> RunID {
        clock.move(to: day(-daysAgo))
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        return try await model.generate(
            HelperReader.Reply.self, schema: schema, task: task, instructions: "v1", input: input, holding: kinds,
            holdingUnknown: unknown
        ).run
    }

    func hasText(_ run: RunID) throws -> Bool { try store.queries.runText(of: run) != nil }
    func runCount() throws -> Int { try store.queries.runs().count }
}

struct RunTextTests {
    @Test func theInputIsKeptWhenARunBeginsAndTheReplyWhenItEnds() async throws {
        let store = try makeStore()
        let open = try store.beginRun(task: "t", model: "m", prompt: "p", input: "hello", kinds: [.screen, .files])
        #expect(try store.queries.runText(of: open) == RunText(input: "hello", reply: nil, kinds: [.screen, .files]))

        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let done = try await model.generate(
            HelperReader.Reply.self, schema: schema, task: "t", instructions: "v1", input: "hi", holding: [.whatsapp]
        ).run
        #expect(
            try store.queries.runText(of: done) == RunText(input: "hi", reply: #"{"items":[]}"#, kinds: [.whatsapp]))
    }

    @Test func aFailedRunKeepsItsInputAndHasNoReply() async throws {
        let store = try makeStore()
        let model = RecordedModel(ScriptedModel(failing: .unavailable("limit")), store: store)
        await #expect(throws: StructuredModelError.unavailable("limit")) {
            _ = try await model.generate(
                HelperReader.Reply.self, schema: schema, task: "t", instructions: "v1", input: "asked",
                holding: [.screen])
        }
        let run = try #require(try store.queries.runs().first)
        #expect(try store.queries.runText(of: run.id) == RunText(input: "asked", reply: nil, kinds: [.screen]))
    }

    @Test func anUnknownKindIsKeptBesideTheKnownOnesAndReadsBack() async throws {
        let timeline = try Timeline()
        let run = try await timeline.run([.screen], unknown: true)
        let plain = try await timeline.run([.screen])
        #expect(
            try timeline.store.queries.runText(of: run)
                == RunText(input: "in", reply: #"{"items":[]}"#, kinds: [.screen], holdsUnknown: true))
        #expect(try timeline.store.queries.runText(of: plain)?.holdsUnknown == false)
    }

    @Test func aRunWithNoTextReadsAsNil() throws {
        #expect(try makeStore().queries.runText(of: 99) == nil)
    }

    @Test func theTextGoesWithItsRun() async throws {
        let timeline = try Timeline()
        let run = try await timeline.run([.screen])
        try await timeline.store.writer.write { try $0.execute(sql: "DELETE FROM run WHERE id = ?", arguments: [run]) }
        #expect(try !timeline.hasText(run))
    }

    @Test func aStoredRunReplaysToTheSameItems() async throws {
        let reply =
            #"{"items":[{"person":"Asha","project":"Login","kind":"done","text":"login done","eta":"","stance":"said","cite":11,"quote":"login"}],"closes":[]}"#
        let evidence = EvidenceSet(
            lines: [Evidence(id: 11, start: t0, line: "Asha: login API done", quotable: ["login API done"])],
            context: ["members": ["Asha"]])
        let store = try makeStore()
        let first = try await HelperReader(spec: .team, model: RecordedModel(ScriptedModel(reply), store: store))
            .read(day: WorkDay(containing: t0), scope: "team", evidence: evidence)
        let firstRun = try #require(first.run)
        let stored = try #require(try store.queries.runText(of: firstRun))
        #expect(stored.kinds == [.whatsapp])

        let replayModel = ScriptedModel(try #require(stored.reply))
        let replayed = try await HelperReader(
            spec: .team, model: RecordedModel(replayModel, store: try makeStore())
        ).read(day: WorkDay(containing: t0), scope: "team", evidence: evidence)
        #expect(replayModel.inputs.withLock { $0 } == [stored.input])
        #expect(replayed.items.map(\.fields) == first.items.map(\.fields))
        #expect(!first.items.isEmpty)
    }
}

struct RunTextDeleteTests {
    private func surviving(_ runs: [RunID], in timeline: Timeline) throws -> [RunID] {
        try runs.filter { try timeline.hasText($0) }
    }

    @Test func aKindDeleteRemovesTextHoldingThatKindBeforeTheCutoffAndKeepsTheRest() async throws {
        let timeline = try Timeline()
        let oldScreen = try await timeline.run([.screen], daysAgo: 10)
        let oldMixed = try await timeline.run([.whatsapp, .screen], daysAgo: 10)
        let oldChat = try await timeline.run([.whatsapp], daysAgo: 10)
        let oldNone = try await timeline.run([], daysAgo: 10)
        let newScreen = try await timeline.run([.screen], daysAgo: 1)
        let all = [oldScreen, oldMixed, oldChat, oldNone, newScreen]

        try timeline.store.delete(.kind(.screen, before: day(-5)))
        #expect(try surviving(all, in: timeline) == [oldChat, oldNone, newScreen])
        try timeline.store.delete(.kind(.screen, before: nil))
        #expect(try surviving(all, in: timeline) == [oldChat, oldNone])
        #expect(try timeline.runCount() == 5)
    }

    @Test func aMachineDeleteRemovesTheTextOfThatMachinesRunsOnly() async throws {
        let timeline = try Timeline()
        let mine = try await timeline.run([.whatsapp], task: "team.ledger")
        let other = try await timeline.run([.whatsapp], task: "day.timeline")
        let prefix = try await timeline.run([.whatsapp], task: "team.ledger.more")
        try timeline.store.delete(.machine("team.ledger"))
        #expect(try surviving([mine, other, prefix], in: timeline) == [other, prefix])
        #expect(try timeline.runCount() == 3)
    }

    @Test func aMachineDeleteAlsoRemovesItsTrialRunTextAndTrialItemsButNotAnotherMachinesTrial() async throws {
        let timeline = try Timeline()
        let mine = try await timeline.run([.whatsapp], task: "team.ledger")
        let myTrial = try await timeline.run([.whatsapp], task: Trial.task(of: "team.ledger"))
        let otherTrial = try await timeline.run([.whatsapp], task: Trial.task(of: "day.timeline"))
        let lookalike = try await timeline.run([.whatsapp], task: Trial.task(of: "team.ledger.more"))
        let store = timeline.store
        func plant(_ task: String, run: RunID) throws {
            let item = Item(
                task: task, day: WorkDay(containing: t0), scope: "", source: .whatsapp, citeFirst: 1, citeLast: 1,
                start: t0, end: t0, fields: ["text": "x"], quote: "x", run: run)
            try store.saveReading(
                .init(items: [item], dropped: 0, run: run), of: .team, day: item.day, scope: "work",
                grant: grant(.whatsapp, label: "work"), pick: { _ in 0 })
        }
        try plant(Trial.task(of: "team.ledger"), run: myTrial)
        try plant(Trial.task(of: "day.timeline"), run: otherTrial)

        try store.delete(.machine("team.ledger"))
        #expect(try surviving([mine, myTrial, otherTrial, lookalike], in: timeline) == [otherTrial, lookalike])
        #expect(try store.queries.items(of: Trial.task(of: "team.ledger"), since: WorkDay(containing: t0)).isEmpty)
        #expect(try store.queries.items(of: Trial.task(of: "day.timeline"), since: WorkDay(containing: t0)).count == 1)
    }

    @Test func aSourceDeleteRemovesTextOfAnUnknownKindWhateverTheKindDeletedAndKeepsKnownOtherKinds() async throws {
        let timeline = try Timeline()
        let unknownOnly = try await timeline.run([], unknown: true, daysAgo: 10)
        let unknownWithChat = try await timeline.run([.whatsapp], unknown: true, daysAgo: 10)
        let unknownNew = try await timeline.run([], unknown: true, daysAgo: 1)
        let chat = try await timeline.run([.whatsapp], daysAgo: 10)
        let none = try await timeline.run([], daysAgo: 10)
        let all = [unknownOnly, unknownWithChat, unknownNew, chat, none]

        try timeline.store.delete(.kind(.screen, before: day(-5)))
        #expect(try surviving(all, in: timeline) == [unknownNew, chat, none], "old unknown text goes; known stays")
        try timeline.store.delete(.activities(ActivityFilter(bundleID: "any")))
        #expect(try surviving(all, in: timeline) == [chat, none], "an activity delete takes it too")
        #expect(try timeline.runCount() == 5)
    }

    @Test func anActivityDeleteRemovesScreenTextAndFileRunsInItsRangeAndKeepsOtherKindsAndTimes() async throws {
        let timeline = try Timeline()
        let inRange = try await timeline.run([.screen], daysAgo: 3)
        let pageText = try await timeline.run([.screenText], daysAgo: 3)
        let files = try await timeline.run([.files], daysAgo: 3)
        let chat = try await timeline.run([.whatsapp], daysAgo: 3)
        let tooOld = try await timeline.run([.screen], daysAgo: 8)
        let tooNew = try await timeline.run([.screen], daysAgo: 0)
        let all = [inRange, pageText, files, chat, tooOld, tooNew]

        try timeline.store.delete(.activities(ActivityFilter(from: day(-5), to: day(-1))))
        #expect(try surviving(all, in: timeline) == [chat, tooOld, tooNew])
        try timeline.store.delete(.activities(ActivityFilter(bundleID: "any")))
        #expect(try surviving(all, in: timeline) == [chat])
        #expect(try timeline.runCount() == 6)
    }

    @Test func anEverythingDeleteRemovesAllTextBeforeTheCutoffWhateverItsKinds() async throws {
        let timeline = try Timeline()
        let oldScreen = try await timeline.run([.screen], daysAgo: 40)
        let oldChat = try await timeline.run([.whatsapp], daysAgo: 40)
        let oldNone = try await timeline.run([], daysAgo: 40)
        let recent = try await timeline.run([.screen], daysAgo: 1)
        try timeline.store.delete(.everything(before: day(-30)))
        #expect(try surviving([oldScreen, oldChat, oldNone, recent], in: timeline) == [recent])
        try timeline.store.delete(.everything(before: nil))
        #expect(try !timeline.hasText(recent))
        #expect(try timeline.runCount() == 4)
    }

    @Test func deletedRunTextIsNotLeftInTheDatabaseOrItsLog() async throws {
        let timeline = try Timeline()
        let secret = "SECRET-\(UUID().uuidString)"
        try await timeline.run([.whatsapp], input: secret)
        func leaks() throws -> Bool {
            try ["workbench.sqlite", "workbench.sqlite-wal"].contains {
                try Data(contentsOf: timeline.store.directory.appending(path: $0)).range(of: Data(secret.utf8)) != nil
            }
        }
        #expect(try leaks())
        try timeline.store.delete(.kind(.whatsapp, before: nil))
        #expect(try !leaks())
    }
}
