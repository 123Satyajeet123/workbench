import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Runs `during` while it answers, as a model call that takes time would let the founder act.
private final class ActingModel: StructuredModel, Sendable {
    let name = "acting"
    private let inner: ScriptedModel
    private let during: @Sendable () -> Void

    init(_ reply: String, during: @escaping @Sendable () -> Void = {}) {
        inner = ScriptedModel(reply)
        self.during = during
    }

    var inputs: [String] { inner.inputs.withLock { $0 } }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        during()
        return try await inner.generate(type, schema: schema, instructions: instructions, input: input)
    }
}

/// Starts a call that never ends by itself, as a slow model does, and fails the way its own error says.
private final class StallingModel: StructuredModel, Sendable {
    let name = "stalling"
    private let startSignal: AsyncStream<Void>
    private let startContinuation: AsyncStream<Void>.Continuation
    let failure: (any Error & Sendable)?

    init(failure: (any Error & Sendable)? = nil) {
        (startSignal, startContinuation) = AsyncStream<Void>.makeStream()
        self.failure = failure
    }

    /// Returns when the first call starts, or when the waiting task is cancelled.
    func waitUntilStarted() async {
        for await _ in startSignal { return }
    }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        startContinuation.yield()
        if let failure { throw failure }
        try await Task.sleep(for: .seconds(60))
        throw URLError(.timedOut)
    }
}

@Suite(.timeLimit(.minutes(1))) struct TimelineModelTests {
    private let noon = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    private let screenOn = CapturePolicy(switches: [.screen: true, .screenText: true])
    private let oneBlock =
        #"{"items":[{"first":1,"last":2,"task":"Build login","project":"app","quote":"login API"}]}"#

    private func at(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: noon)!
    }

    /// A store with a morning of screen activity: a terminal, a pull request with its page text, then idle.
    private func morning() throws -> Store {
        let clock = TestClock(at(hour: 9))
        let store = try scratchStore(clock: { clock.now })
        try store.savePolicy(screenOn)
        var engine = CaptureEngine()
        let snapshots = [
            (at(hour: 9), ScreenSnapshot(app: "Terminal", bundleID: "t", windowID: 1, title: "app — claude", text: "")),
            (
                at(hour: 9, minute: 40),
                ScreenSnapshot(
                    app: "Brave", bundleID: "b", windowID: 2, document: "https://github.com/x/app/pull/12",
                    title: "Pull request · login API", text: "SECRET page body")
            ),
        ]
        for (time, snapshot) in snapshots {
            clock.set(time)
            let batch = engine.observe(snapshot, idleSeconds: 0, policy: screenOn, at: time)
            try store.record(#require(batch))
        }
        clock.set(at(hour: 10, minute: 30))
        let idle = engine.observe(snapshots[1].1, idleSeconds: 600, policy: screenOn, at: at(hour: 10, minute: 30))
        try store.record(#require(idle))
        clock.set(noon)
        return store
    }

    private func model(_ store: Store, _ model: ActingModel) -> HelperModel {
        HelperModel(
            machine: .test(.timeline, "Timeline"), source: ScreenSource(store: store), store: store,
            makeModel: { _ in RecordedModel(model, store: store) })
    }

    @Test func readingADaySendsTitlesAndAddressesButNotScreenTextAndStoresCheckedBlocks() async throws {
        let store = try morning()
        let acting = ActingModel(oneBlock)
        let timeline = model(store, acting)
        let screen = try #require(timeline.source as? ScreenSource)
        #expect(screen.sessions.count == 2)
        #expect(screen.sessions.reduce(0) { $0 + $1.minutes } == 90)
        await timeline.read()
        let input = try #require(acting.inputs.first)
        #expect(input.contains("Pull request · login API — https://github.com/x/app/pull/12"))
        #expect(!input.contains("SECRET"))
        #expect(timeline.items.map { $0["task"] } == ["Build login"])
        #expect(try timeline.items.first?.run == store.queries.runs().first?.id)
        #expect(timeline.phase == .read(kept: 1, dropped: 0))
    }

    @Test func withScreenCaptureOffNothingIsSent() async throws {
        let store = try morning()
        try store.savePolicy(CapturePolicy(switches: [.screen: false]))
        let acting = ActingModel(oneBlock)
        let timeline = model(store, acting)
        await timeline.read()
        #expect(acting.inputs.isEmpty)
        #expect(timeline.problem?.hasPrefix("Could not read the day") == true)
        #expect(timeline.mood == .trouble)
        #expect(try store.queries.runs().isEmpty)
    }

    @Test func consentWithdrawnDuringTheReadStopsTheWrite() async throws {
        let store = try morning()
        let acting = ActingModel(oneBlock) { try? store.savePolicy(CapturePolicy(switches: [.screen: false])) }
        let timeline = model(store, acting)
        await timeline.read()
        #expect(acting.inputs.count == 1)
        #expect(timeline.items.isEmpty)
        #expect(timeline.problem != nil)
    }

    private func stalling(_ store: Store, _ model: StallingModel) -> HelperModel {
        HelperModel(
            machine: .test(.timeline, "Timeline"), source: ScreenSource(store: store), store: store,
            makeModel: { _ in RecordedModel(model, store: store) })
    }

    @Test func aCancelledReadingLeavesNoProblemShown() async throws {
        let model = StallingModel()
        let timeline = stalling(try morning(), model)
        let reading = Task { await timeline.read() }
        let reachedTheModel = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await model.waitUntilStarted(); return true }
            group.addTask { await reading.value; return false }
            let first = await group.next() ?? false
            reading.cancel()
            group.cancelAll()
            return first
        }
        #expect(reachedTheModel, "the reading ended before it called the model")
        await reading.value
        #expect(timeline.problem == nil)
        #expect(timeline.phase == .idle)
    }

    @Test func aReadingThatFailsStillShowsTheProblem() async throws {
        let model = StallingModel(failure: URLError(.notConnectedToInternet))
        let timeline = stalling(try morning(), model)
        await timeline.read()
        #expect(timeline.problem?.hasPrefix("Could not read the day: ") == true)
        #expect(timeline.phase == .idle)
    }
}
