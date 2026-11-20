import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct MorningBriefTests {
    private let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 8))!

    @Test func theBriefOfYesterdayComesOnceEachMorningOnlyWhenOn() async throws {
        let clock = TestClock(morning)
        let store = try scratchStore(clock: { clock.now })
        try store.savePolicy(CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: ["team"]]))
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let yesterday = WorkDay(containing: morning).adding(days: -1)
        let recorder = RecordedModel(ScriptedModel(#"{}"#), store: store)
        let (_, run) = try await recorder.generate(
            Nothing.self, schema: .object([]), task: HelperSpec.team.task, instructions: "v1", input: "x", holding: [])
        let blocker = Item(
            task: HelperSpec.team.task, day: yesterday, scope: "", source: .whatsapp, citeFirst: 5, citeLast: 5,
            start: yesterday.start.addingTimeInterval(36_000), end: yesterday.start.addingTimeInterval(36_000),
            fields: ["person": "Asha", "kind": "blocker", "text": "No OTA push yet", "eta": ""], quote: "nai aaya",
            run: run)
        try store.saveReading(
            .init(items: [blocker], dropped: 0, run: run), of: .team, day: yesterday, scope: "",
            grant: try await store.grant(for: .whatsapp, label: "team", at: store.clock()))
        let model = KeyedModel([
            "Write the morning brief":
                #"{"headline":"Asha is blocked until the OTA is pushed.","lines":[{"kind":"stuck","basis":"seen","text":"Asha waits for the OTA push.","cites":[@nai aaya@]},{"kind":"next","basis":"inferred","text":"Push the OTA to Asha's device first.","cites":[@nai aaya@]}]}"#
        ])
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        let mochi = MochiModel(store: store, crew: crew, makeModel: { _ in RecordedModel(model, store: store) })
        let notifier = FakeNotifier()
        let reminders = Reminders(
            store: store, review: ReviewModel(store: store, crew: crew), mochi: mochi, notifier: notifier)

        clock.set(morning.addingTimeInterval(2 * 3600))
        await reminders.tick()
        #expect(mochi.brief == nil && model.calls.withLock { $0 } == 0, "off by default")

        await reminders.setMorningBrief(on: true)
        clock.set(morning)
        await reminders.tick()
        #expect(mochi.brief == nil, "not before nine")

        clock.set(morning.addingTimeInterval(90 * 60))
        await reminders.tick()
        let brief = try #require(mochi.brief)
        #expect(brief.day == yesterday.description && brief.lines.map(\.kind) == [.stuck, .next])
        #expect(notifier.posted.map(\.body) == ["Asha is blocked until the OTA is pushed."])
        #expect(notifier.posted.map(\.page) == [.day], "a click opens Mochi's day")
        #expect(brief.unseen == ["Timeline"], "the timeline found nothing that day")
        await reminders.tick()
        #expect(model.calls.withLock { $0 } == 1, "once a morning")
        let reopened = MochiModel(store: store, crew: crew)
        #expect(reopened.brief == brief, "the brief is kept")
    }

    @Test func aQuietDayIsKeptWithoutAnAlert() async throws {
        let clock = TestClock(morning.addingTimeInterval(90 * 60))
        let store = try scratchStore(clock: { clock.now })
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let yesterday = WorkDay(containing: morning).adding(days: -1)
        let recorder = RecordedModel(ScriptedModel(#"{}"#), store: store)
        let (_, run) = try await recorder.generate(
            Nothing.self, schema: .object([]), task: HelperSpec.team.task, instructions: "v1", input: "x", holding: [])
        try store.savePolicy(CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: ["team"]]))
        let done = Item(
            task: HelperSpec.team.task, day: yesterday, scope: "", source: .whatsapp, citeFirst: 5, citeLast: 5,
            start: yesterday.start, end: yesterday.start,
            fields: ["person": "Asha", "kind": "done", "text": "Shipped"],
            quote: "shipped", run: run)
        try store.saveReading(
            .init(items: [done], dropped: 0, run: run), of: .team, day: yesterday, scope: "",
            grant: try await store.grant(for: .whatsapp, label: "team", at: store.clock()))
        let model = KeyedModel([
            "Write the morning brief":
                #"{"headline":"A quiet day.","lines":[{"kind":"happened","basis":"seen","text":"Asha shipped.","cites":[@shipped@]}]}"#
        ])
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        let mochi = MochiModel(store: store, crew: crew, makeModel: { _ in RecordedModel(model, store: store) })
        let notifier = FakeNotifier()
        let reminders = Reminders(
            store: store, review: ReviewModel(store: store, crew: crew), mochi: mochi, notifier: notifier)
        await reminders.setMorningBrief(on: true)
        await reminders.tick()
        #expect(mochi.brief?.isQuiet == true && notifier.posted.isEmpty)
    }
}
