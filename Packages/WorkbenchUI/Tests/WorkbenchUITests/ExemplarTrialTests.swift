import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct ExemplarTrialTests {
    private let current =
        #"{"items":[{"task":"Review the PR","project":"","first":1,"last":1,"quote":"PR"},{"task":"Chat","project":"","first":2,"last":2,"quote":"Staff"}]}"#

    @Test func learningFromMarksIsTriedThenSwitchedThenRolledBackByTheAlarm() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let store = try scratchStore(clock: { clock.now })
        let on = CapturePolicy(switches: [.screen: true])
        try store.savePolicy(on)
        let today = WorkDay(containing: clock.now)
        let devDays = (1...20).map { today.adding(days: -$0) }.filter { EvalSplit($0) == .dev }.prefix(3)
        var engine = CaptureEngine()
        let start = clock.now
        for day in devDays {
            for (index, title) in ["Open PR", "Brave Staff"].enumerated() {
                clock.set(day.start.addingTimeInterval(Double(4 + index) * 3600))
                let snapshot = ScreenSnapshot(app: "App", bundleID: "a", windowID: index, title: title, text: "")
                let batch = engine.observe(snapshot, idleSeconds: 0, policy: on, at: clock.now)
                try store.record(#require(batch))
            }
            clock.set(day.start.addingTimeInterval(8 * 3600))
            let idle = ScreenSnapshot(app: "App", bundleID: "a", windowID: 9, title: "x", text: "")
            let batch = engine.observe(idle, idleSeconds: 600, policy: on, at: clock.now)
            try store.record(#require(batch))
        }
        clock.set(start)
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let model = KeyedModel([HelperSpec.timeline.brief: current])
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" },
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: FakeNotifier())
        let timeline = try #require(crew.timeline)
        for day in devDays {
            timeline.show(day)
            await timeline.read()
            for item in timeline.items {
                timeline.mark(item, as: item.quote == "Staff" ? .rejected : .confirmed)
            }
        }
        let callsBefore = model.calls.withLock { $0 }

        await timeline.learnFromMarks()
        let trial = try #require(timeline.trial)
        #expect(trial.examples == 5 && trial.brief == HelperSpec.timeline.brief)
        #expect(timeline.spec.examples == nil, "the live machine does not change")
        #expect(model.calls.withLock { $0 } - callsBefore == 3, "one replay call per marked training day")
        let replayed = model.inputs.withLock { Array($0.suffix(3)) }
        #expect(replayed.allSatisfy { $0.hasPrefix("Examples the founder marked on other days:") })
        #expect(replayed.allSatisfy { $0.contains("- wrong: task=Chat") }, "it sees its own past mistakes")

        crew.switchToTrial(timeline)
        #expect(timeline.spec.examples == 5)
        let switched = try #require(try store.queries.decisions(of: timeline.spec.task).first)
        #expect(
            switched.kind == .promote && switched.detail["examples"] == "5" && switched.detail["parentExamples"] == "")

        clock.set(start.addingTimeInterval(3600))
        let heldOut = (1...60).map { today.adding(days: -$0) }.filter { EvalSplit($0) == .heldOut }.prefix(2)
        for day in heldOut {
            clock.set(clock.now.addingTimeInterval(60))
            let recorded = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
            let (_, run) = try await recorded.generate(
                Nothing.self, schema: .object([]), task: timeline.spec.task, instructions: "v", input: "x")
            let item = Item(
                task: timeline.spec.task, day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1,
                start: day.start, end: day.start.addingTimeInterval(600), fields: ["task": "t"], quote: "q", run: run)
            try store.saveReading(
                .init(items: [item], dropped: 0, run: run), of: timeline.spec, day: day, scope: "",
                grant: try await store.grant(for: .screen, at: clock.now), pick: { _ in 0 })
            timeline.show(day)
            timeline.mark(try #require(timeline.items.first), as: .rejected)
        }
        #expect(timeline.spec.examples == nil, "the rollback restores the earlier example policy")
        #expect(try store.queries.decisions(of: timeline.spec.task).first?.kind == .rollback)
    }
}
