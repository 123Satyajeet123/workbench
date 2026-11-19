import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct ReminderTests {
    private let monday = Calendar.current.date(
        from: DateComponents(year: 2026, month: 11, day: 16, hour: 8))!

    private func at(_ hour: Int, plusDays days: Int = 0) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: monday)!.addingTimeInterval(Double(hour - 8) * 3600)
    }

    /// A store with timeline blocks waiting on `count` training days before `monday`, and the models over it.
    private func setup(trainingDays count: Int, proposals: String = #"{"proposals":[]}"#) async throws -> (
        Reminders, FakeNotifier, TestClock, ScriptedModel
    ) {
        let clock = TestClock(monday)
        let store = try scratchStore(clock: { clock.now })
        try store.savePolicy(CapturePolicy(switches: [.screen: true]))
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        let today = WorkDay(containing: monday)
        let days = (1...30).map { today.adding(days: -$0) }.filter { EvalSplit($0) == .dev }.prefix(count)
        let recorder = RecordedModel(ScriptedModel(#"{}"#), store: store)
        for day in days {
            let (_, run) = try await recorder.generate(
                Nothing.self, schema: .object([]), task: HelperSpec.timeline.task, instructions: "v1", input: "x")
            let block = Item(
                task: HelperSpec.timeline.task, day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1,
                start: day.start.addingTimeInterval(3600), end: day.start.addingTimeInterval(7200),
                fields: ["task": "Triage decks", "project": ""], quote: "Deck", run: run)
            try store.saveReading(
                .init(items: [block], dropped: 0, run: run), of: .timeline, day: day, scope: "",
                grant: try await store.grant(for: .screen, at: store.clock()))
        }
        let scripted = ScriptedModel(proposals)
        let review = ReviewModel(store: store, crew: crew)
        let mochi = MochiModel(store: store, crew: crew, makeModel: { _ in RecordedModel(scripted, store: store) })
        let notifier = FakeNotifier()
        return (Reminders(store: store, review: review, mochi: mochi, notifier: notifier), notifier, clock, scripted)
    }

    @Test func theDigestSlotIsTheLatestHourAlreadyPassedToday() {
        #expect(Reminders.slot(at: at(8), hours: [9, 15]) == nil)
        #expect(Reminders.slot(at: at(10), hours: [9, 15])?.hasSuffix(" 09") == true)
        #expect(Reminders.slot(at: at(16), hours: [9, 15])?.hasSuffix(" 15") == true)
        #expect(Reminders.slot(at: at(10), hours: [9, 15]) != Reminders.slot(at: at(10, plusDays: 1), hours: [9, 15]))
    }

    @Test func theDigestComesOncePerSlotOnlyWhenSomethingWaitsAndNeverWhenOff() async throws {
        let (reminders, notifier, clock, _) = try await setup(trainingDays: 1)
        clock.set(at(10))
        await reminders.tick()
        #expect(notifier.posted.isEmpty, "off by default")
        await reminders.setDigest(on: true)
        await reminders.tick()
        #expect(notifier.posted.map(\.body) == ["1 to review, 1 picked at random. Open Workbench › Review."])
        clock.set(at(11))
        await reminders.tick()
        #expect(notifier.posted.count == 1, "once per slot")
        clock.set(at(16))
        await reminders.tick()
        #expect(notifier.posted.count == 2, "the next slot")
    }

    @Test func mochiRunsWeeklyInTheEveningWhenOnAndNotTwice() async throws {
        let (reminders, notifier, clock, scripted) = try await setup(trainingDays: 3)
        clock.set(at(19))
        await reminders.tick()
        #expect(scripted.inputs.withLock { $0.isEmpty }, "off by default")
        reminders.settings.weeklyMochi = true
        clock.set(at(17))
        await reminders.tick()
        #expect(scripted.inputs.withLock { $0.isEmpty }, "not before the evening")
        clock.set(at(19))
        await reminders.tick()
        #expect(scripted.inputs.withLock { $0.count } == 1)
        clock.set(at(20, plusDays: 2))
        await reminders.tick()
        #expect(scripted.inputs.withLock { $0.count } == 1, "once a week")
        clock.set(at(19, plusDays: 7))
        await reminders.tick()
        #expect(scripted.inputs.withLock { $0.count } == 2)
        #expect(notifier.posted.isEmpty, "no notice without new proposals")
    }
}
