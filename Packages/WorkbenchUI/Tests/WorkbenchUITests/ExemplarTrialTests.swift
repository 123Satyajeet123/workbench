import CaptureService
import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct ExemplarTrialTests {
    private let current =
        #"{"items":[{"task":"Review the PR","project":"","first":@Open PR@,"last":@Open PR@,"quote":"PR"},{"task":"Chat","project":"","first":@Brave Staff@,"last":@Brave Staff@,"quote":"Staff"}]}"#

    @Test func learningFromMarksIsTriedThenSwitchedThenRolledBackByTheAlarm() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let store = try scratchStore(clock: { clock.now })
        let on = CapturePolicy(switches: [.screen: true])
        try store.savePolicy(on)
        let today = WorkDay(containing: clock.now)
        let recent = (1...20).map { today.adding(days: -$0) }
        let devDays =
            Array(recent.filter { DevHalf($0) == .learn }.prefix(3))
            + Array(recent.filter { DevHalf($0) == .trial }.prefix(3))
        var engine = CaptureEngine()
        let start = clock.now
        for day in devDays {
            for (index, title) in ["Open PR", "Brave Staff"].enumerated() {
                clock.set(day.start.addingTimeInterval(Double(4 + index) * 3600))
                let snapshot = ScreenSnapshot(app: "App", bundleID: "a", windowID: index, title: title, text: "")
                let batch = engine.observe(snapshot, presence: .active, policy: on, at: clock.now)
                try store.record(#require(batch))
            }
            clock.set(day.start.addingTimeInterval(8 * 3600))
            let idle = ScreenSnapshot(app: "App", bundleID: "a", windowID: 9, title: "x", text: "")
            let batch = engine.observe(idle, presence: .idle, policy: on, at: clock.now)
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
        #expect(trial.version.examples == 5 && trial.version.brief == HelperSpec.timeline.brief)
        #expect(timeline.spec.examples == nil, "the live machine does not change")
        #expect(model.calls.withLock { $0 } - callsBefore == 3, "one replay call per marked trial day")
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
                Nothing.self, schema: .object([.init("items", .array(.string))]), task: timeline.spec.task,
                instructions: "v", input: "x", holding: [])
            let item = Item(
                task: timeline.spec.task, day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1,
                start: day.start, end: day.start.addingTimeInterval(600), fields: ["task": "t"], quote: "q", run: run)
            try store.saveReading(
                .init(items: [item], dropped: 0, run: run), of: timeline.spec, day: day, scope: "",
                grant: try await store.grant(for: .screen, at: clock.now), isAudited: { $0 == 0 })
            timeline.show(day)
            timeline.mark(try #require(timeline.items.first), as: .rejected)
        }
        #expect(timeline.spec.examples == nil, "the rollback restores the earlier example policy")
        #expect(try store.queries.decisions(of: timeline.spec.task).first?.kind == .rollback)
    }

    @Test func anotherModelIsTriedOnPastDaysThenTheMachineKeepsItAndARollbackReturnsIt() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let store = try scratchStore(clock: { clock.now })
        let on = CapturePolicy(switches: [.screen: true])
        try store.savePolicy(on)
        let today = WorkDay(containing: clock.now)
        let devDay = try #require((1...20).map { today.adding(days: -$0) }.first { DevHalf($0) == .trial })
        var engine = CaptureEngine()
        let start = clock.now
        for (index, title) in ["Open PR", "Brave Staff"].enumerated() {
            clock.set(devDay.start.addingTimeInterval(Double(4 + index) * 3600))
            let snapshot = ScreenSnapshot(app: "App", bundleID: "a", windowID: index, title: title, text: "")
            let batch = engine.observe(snapshot, presence: .active, policy: on, at: clock.now)
            try store.record(#require(batch))
        }
        clock.set(devDay.start.addingTimeInterval(8 * 3600))
        let idle = engine.observe(
            ScreenSnapshot(app: "App", bundleID: "a", windowID: 9, title: "x", text: ""), presence: .idle, policy: on,
            at: clock.now)
        try store.record(#require(idle))
        clock.set(start)
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let asked = Mutex<[String]>([])
        let model = KeyedModel([HelperSpec.timeline.brief: current])
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" },
            makeModel: { choice in
                asked.withLock { $0.append(choice.id) }
                return RecordedModel(model, store: store)
            }, notifier: FakeNotifier())
        let timeline = try #require(crew.timeline)
        timeline.show(devDay)
        await timeline.read()
        for item in timeline.items { timeline.mark(item, as: .confirmed) }
        let sonnet = try #require(ModelChoice.with(id: "claude sonnet"))

        await timeline.tryModel(sonnet)
        #expect(timeline.trial?.version.runner == "claude sonnet" && timeline.spec.runner == nil)
        #expect(asked.withLock { $0 } == ["claude opus", "claude sonnet"], "the trial reads with the tried model")

        crew.switchToTrial(timeline)
        #expect(timeline.spec.runner == "claude sonnet")
        timeline.show(devDay)
        await timeline.read()
        #expect(
            asked.withLock { $0.last } == "claude sonnet", "the machine keeps its model; the global pick is unchanged")
        #expect(try ModelChoice.saved(in: store).id == "claude opus")

        let switched = try #require(try store.queries.decisions(of: timeline.spec.task).first)
        #expect(switched.detail["runner"] == "claude sonnet" && switched.detail["parentRunner"] == "")
        let heldOut = (1...60).map { today.adding(days: -$0) }.filter { EvalSplit($0) == .heldOut }.prefix(2)
        for day in heldOut {
            clock.set(clock.now.addingTimeInterval(3600))
            let recorded = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
            let (_, run) = try await recorded.generate(
                Nothing.self, schema: .object([.init("items", .array(.string))]), task: timeline.spec.task,
                instructions: "v", input: "x", holding: [])
            let item = Item(
                task: timeline.spec.task, day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1,
                start: day.start, end: day.start.addingTimeInterval(600), fields: ["task": "t"], quote: "q", run: run)
            try store.saveReading(
                .init(items: [item], dropped: 0, run: run), of: timeline.spec, day: day, scope: "",
                grant: try await store.grant(for: .screen, at: clock.now), isAudited: { $0 == 0 })
            timeline.show(day)
            timeline.mark(try #require(timeline.items.first), as: .rejected)
        }
        #expect(timeline.spec.runner == nil, "the rollback returns the machine to the founder's model")
    }
}
