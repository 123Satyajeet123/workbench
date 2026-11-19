import CaptureService
import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Answers with the reply whose key its instructions contain: the current brief and the new one read differently.
private final class BriefModel: StructuredModel, Sendable {
    let name = "briefs"
    private let replies: [String: String]
    let calls = Mutex(0)

    init(_ replies: [String: String]) { self.replies = replies }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        calls.withLock { $0 += 1 }
        let reply = replies.first { instructions.contains($0.key) }?.value ?? #"{"items":[]}"#
        return ModelAnswer(value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: "m", usage: Usage())
    }
}

@Suite struct TrialTests {
    private let current =
        #"{"items":[{"task":"Review the PR","project":"","first":1,"last":1,"quote":"PR"},{"task":"Chat","project":"","first":2,"last":2,"quote":"Staff"}]}"#
    private let tried =
        #"{"items":[{"task":"Review the pull request","project":"","first":1,"last":1,"quote":"PR"},{"task":"Write the memo","project":"","first":3,"last":3,"quote":"Memo"}]}"#

    @Test func aNewBriefIsTriedOnPastDaysBesideTheCurrentAndOnlySwitchingChangesTheMachine() async throws {
        let clock = TestClock(.now)
        let store = try scratchStore(clock: { clock.now })
        let on = CapturePolicy(switches: [.screen: true])
        try store.savePolicy(on)
        let today = WorkDay(containing: .now)
        let days = (1...14).map { today.adding(days: -$0) }.filter { EvalSplit($0) == .dev }.prefix(2)
        var engine = CaptureEngine()
        for day in days {
            for (index, title) in ["Open PR", "Brave Staff", "Memo draft"].enumerated() {
                clock.set(day.start.addingTimeInterval(Double(4 + index) * 3600))
                let snapshot = ScreenSnapshot(app: "App", bundleID: "a", windowID: index, title: title, text: "")
                let batch = engine.observe(snapshot, idleSeconds: 0, policy: on, at: clock.now)
                try store.record(#require(batch))
            }
            clock.set(day.start.addingTimeInterval(8 * 3600))
            let batch = engine.observe(
                ScreenSnapshot(app: "App", bundleID: "a", windowID: 9, title: "x", text: ""), idleSeconds: 600,
                policy: on, at: clock.now)
            try store.record(#require(batch))
        }
        clock.set(.now)
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let model = BriefModel([HelperSpec.timeline.brief: current, "memos": tried])
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" },
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: FakeNotifier())
        let timeline = try #require(crew.timeline)
        for day in days {
            timeline.show(day)
            await timeline.read()
            for item in timeline.items where item.quote == "Staff" { timeline.mark(item, as: .rejected) }
        }

        await timeline.startTrial(brief: "Join windows into blocks; include writing memos.")
        let trial = try #require(timeline.trial)
        #expect(trial.days.count == 2)
        #expect(trial.result.same == 2 && trial.result.added.count == 2 && trial.result.dropped.count == 2)
        #expect(trial.result.better == 2 && trial.result.worse == 0 && trial.result.waiting == 2)
        #expect(timeline.spec.brief == HelperSpec.timeline.brief, "the live machine does not change")
        let review = ReviewModel(store: store, crew: crew)
        #expect(review.items.contains { review.name(of: $0) == "Timeline · new brief" })

        crew.switchToTrial(timeline)
        #expect(timeline.spec.brief == "Join windows into blocks; include writing memos.")
        #expect(timeline.trial == nil)
        #expect(try store.queries.items(of: Trial.task(of: timeline.spec.task), since: today.adding(days: -14)).isEmpty)
    }
}
