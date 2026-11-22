import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

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

private final class StallingModel: StructuredModel, Sendable {
    let name = "stalling"
    let started = Mutex(false)
    let failure: (any Error & Sendable)?

    init(failure: (any Error & Sendable)? = nil) { self.failure = failure }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        started.withLock { $0 = true }
        if let failure { throw failure }
        try await Task.sleep(for: .seconds(60))
        throw URLError(.timedOut)
    }
}

@Suite struct TimelineModelTests {
    private let noon = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    private let screenOn = CapturePolicy(switches: [.screen: true, .screenText: true])
    private let oneBlock =
        #"{"items":[{"first":1,"last":2,"task":"Build login","project":"app","quote":"login API"}]}"#

    private func at(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: noon)!
    }

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
        while !model.started.withLock({ $0 }) { await Task.yield() }
        reading.cancel()
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
