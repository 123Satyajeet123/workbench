import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// After a switch, the new brief's held-out audit answers decide whether the machine rolls back by itself.
@Suite struct RollbackTests {
    private struct Setup {
        let store: Store
        let crew: Crew
        let timeline: HelperModel
        let notifier: FakeNotifier
        let clock: TestClock
    }

    private func setup() throws -> Setup {
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let store = try scratchStore(clock: { clock.now })
        try store.savePolicy(CapturePolicy(switches: [.screen: true]))
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let notifier = FakeNotifier()
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" },
            makeModel: { _ in RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store) }, notifier: notifier)
        return Setup(store: store, crew: crew, timeline: try #require(crew.timeline), notifier: notifier, clock: clock)
    }

    /// Switches the timeline from its brief to "New brief", as the founder's Switch button logs it.
    private func switchBrief(_ s: Setup) {
        let parent = s.timeline.spec.brief
        s.crew.edit(s.timeline, brief: "New brief")
        try? s.store.log(
            Decision(
                at: s.clock.now, task: s.timeline.spec.task, kind: .promote, by: .person, brief: "New brief",
                parentBrief: parent))
    }

    /// One reading of `day` whose item is the audit pick, then the founder's answer to it.
    private func audit(_ s: Setup, on day: WorkDay, wrong: Bool) async throws {
        answer(s, try await read(s, on: day), wrong: wrong)
    }

    private func answer(_ s: Setup, _ item: Item, wrong: Bool) {
        s.clock.set(s.clock.now.addingTimeInterval(60))
        s.timeline.show(item.day)
        s.timeline.mark(item, as: wrong ? .rejected : .confirmed)
    }

    /// One reading of `day` whose single item is the audit pick.
    private func read(_ s: Setup, on day: WorkDay) async throws -> Item {
        s.clock.set(s.clock.now.addingTimeInterval(60))
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: s.store)
        let (_, run) = try await model.generate(
            Nothing.self, schema: .object([]), task: s.timeline.spec.task, instructions: "v", input: "x")
        let item = Item(
            task: s.timeline.spec.task, day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1,
            start: day.start, end: day.start.addingTimeInterval(600), fields: ["task": "t\(run)"], quote: "q", run: run)
        try s.store.saveReading(
            .init(items: [item], dropped: 0, run: run), of: s.timeline.spec, day: day, scope: "",
            grant: try await s.store.grant(for: .screen, at: s.clock.now), pick: { _ in 0 })
        s.timeline.show(day)
        return try #require(s.timeline.items.last { $0.fields["task"] == "t\(run)" })
    }

    private func days(_ split: EvalSplit, _ count: Int, before now: Date) -> [WorkDay] {
        Array(
            (1...60).map { WorkDay(containing: now).adding(days: -$0) }.filter { EvalSplit($0) == split }.prefix(count))
    }

    @Test func twoWrongHeldOutAnswersAfterASwitchRollTheBriefBackAndSaySo() async throws {
        let s = try setup()
        let original = s.timeline.spec.brief
        switchBrief(s)
        let heldOut = days(.heldOut, 2, before: s.clock.now)
        try await audit(s, on: heldOut[0], wrong: true)
        #expect(s.timeline.spec.brief == "New brief", "one wrong answer is not enough")
        try await audit(s, on: heldOut[1], wrong: true)
        #expect(s.timeline.spec.brief == original)
        #expect(try s.store.queries.decisions(of: s.timeline.spec.task).first?.kind == .rollback)
        #expect(s.timeline.notice?.contains("wrong on 2 of 2") == true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(s.notifier.posted.count == 1)
    }

    @Test func rightAnswersTrainingDaysAndTheOldBriefsItemsNeverTriggerIt() async throws {
        let s = try setup()
        let heldOut = days(.heldOut, 4, before: s.clock.now)
        let oldItems = [try await read(s, on: heldOut[0]), try await read(s, on: heldOut[1])]
        switchBrief(s)
        for item in oldItems { answer(s, item, wrong: true) }
        #expect(s.timeline.spec.brief == "New brief", "the old brief's items, answered after the switch, do not count")
        for day in days(.dev, 3, before: s.clock.now) { try await audit(s, on: day, wrong: true) }
        try await audit(s, on: heldOut[2], wrong: false)
        try await audit(s, on: heldOut[3], wrong: false)
        #expect(s.timeline.spec.brief == "New brief")
        #expect(try s.store.queries.decisions(of: s.timeline.spec.task).map(\.kind) == [.promote])
    }

    @Test func withNoEarlierVersionTheAlarmWarnsOnceAndChangesNothing() async throws {
        let s = try setup()
        let heldOut = days(.heldOut, 3, before: s.clock.now)
        try await audit(s, on: heldOut[0], wrong: true)
        #expect(s.timeline.notice == nil)
        try await audit(s, on: heldOut[1], wrong: true)
        #expect(s.timeline.spec.brief == HelperSpec.timeline.brief, "nothing to roll back to, nothing changes")
        #expect(s.timeline.notice?.contains("may have got worse") == true)
        try await audit(s, on: heldOut[2], wrong: true)
        try await Task.sleep(for: .milliseconds(50))
        #expect(s.notifier.posted.count == 1, "once per version")
        #expect(try s.store.queries.decisions(of: s.timeline.spec.task).isEmpty)
    }

    @Test func rightAnswersNeverWarn() async throws {
        let s = try setup()
        for day in days(.heldOut, 4, before: s.clock.now) { try await audit(s, on: day, wrong: false) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(s.timeline.notice == nil && s.notifier.posted.isEmpty)
    }
}
