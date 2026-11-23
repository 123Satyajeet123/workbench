import CaptureService
import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Measured on the founder's day: reading twice re-sent the whole day and kept a reworded duplicate of a marked item.
@Suite struct ReadingTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private struct Setup {
        let pip: HelperModel
        let model: KeyedModel
        let notifier: FakeNotifier
        let container: URL
        let clock: TestClock
        let store: Store
    }

    private func setup(reply: String) throws -> Setup {
        let clock = TestClock(noon)
        let store = try scratchStore(clock: { clock.now })
        let container = try whatsApp(at: noon)
        let machine = try store.createMachine(from: .team, name: "Pip")
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: machine.task, founder: { "Kabir" },
            container: container)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        let model = KeyedModel(["team ledger": reply])
        let notifier = FakeNotifier()
        let pip = HelperModel(
            machine: machine, source: source, store: store, makeModel: { _ in RecordedModel(model, store: store) },
            notifier: notifier)
        return Setup(pip: pip, model: model, notifier: notifier, container: container, clock: clock, store: store)
    }

    @Test func aSecondReadingSendsOnlyNewLinesAndNeverReReadsOrDuplicates() async throws {
        let s = try setup(
            reply:
                #"{"items":[{"person":"Asha","project":"Login","kind":"done","text":"Login API","when":{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""},"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":@login API done@,"quote":"login API done"}]}"#
        )
        await s.pip.read()
        #expect(s.pip.items.count == 1)

        await s.pip.read()
        #expect(s.pip.phase == .upToDate)
        #expect(s.model.calls.withLock { $0 } == 1, "nothing new, no call")

        try addMessage(30, "payments blocked on keys", at: noon.addingTimeInterval(600), to: s.container)
        s.model.replies.withLock {
            $0["team ledger"] =
                #"{"items":[{"person":"Asha","project":"Login","kind":"done","text":"Login API reworded","when":{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""},"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":@login API done@,"quote":"login API done"},{"person":"Asha","project":"Login","kind":"blocker","text":"Payments blocked","when":{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""},"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":@payments blocked on keys@,"quote":"payments blocked on keys"}]}"#
        }
        await s.pip.read()
        #expect(s.pip.phase == .read(kept: 1, dropped: 1), "a line read before cannot be cited again")
        #expect(s.pip.items.map(\.quote) == ["login API done", "payments blocked on keys"])
    }

    @Test func aReadingBringsTheDaysSummariesUpToDateByPersonAndByProject() async throws {
        let s = try setup(
            reply:
                #"{"items":[{"person":"Asha","project":"Login","kind":"done","text":"Login API","when":{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""},"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":@login API done@,"quote":"login API done"}]}"#
        )
        await s.pip.read()
        #expect(s.model.summaryCalls.withLock { $0 } == 2, "one set of summaries for people, one for projects")
        #expect(s.model.calls.withLock { $0 } == 1, "the reading itself is one call")
    }

    @Test func readingThroughTheDayAlertsOnlyForNewBlockersAndOnlyInsideItsHours() async throws {
        let s = try setup(
            reply:
                #"{"items":[{"person":"Asha","project":"Login","kind":"blocker","text":"Waiting for keys","when":{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""},"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":@login API done@,"quote":"login API done"},{"person":"Asha","project":"Login","kind":"done","text":"Login API","when":{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""},"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":@login API done@,"quote":"login API"}]}"#
        )
        s.pip.watch = WatchSchedule(isOn: true, everyMinutes: 60, fromHour: 9, untilHour: 22)
        await s.pip.readIfDue()
        #expect(s.notifier.posted.map(\.body) == ["Asha: Waiting for keys"])
        await s.pip.readIfDue()
        #expect(s.model.calls.withLock { $0 } == 1, "not again within the hour")

        s.clock.set(noon.addingTimeInterval(3600))
        await s.pip.readIfDue()
        #expect(s.pip.phase == .upToDate && s.notifier.posted.count == 1, "nothing new, no alert")

        s.clock.set(Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: noon)!)
        try addMessage(31, "still blocked", at: s.clock.now, to: s.container)
        await s.pip.readIfDue()
        #expect(s.model.calls.withLock { $0 } == 1, "outside the reading hours")
    }
}

@Suite struct TimelineReadingTests {
    @Test func theTimelineReadsNewWindowsAndHoldsTheOpenOneUntilItCloses() async throws {
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        let clock = TestClock(start)
        let store = try scratchStore(clock: { clock.now })
        let on = CapturePolicy(switches: [.screen: true])
        try store.savePolicy(on)
        var engine = CaptureEngine()
        func window(_ title: String, at minutes: Double, idle: Bool = false) throws {
            clock.set(start.addingTimeInterval(minutes * 60))
            let snapshot = ScreenSnapshot(app: "App", bundleID: "a", windowID: title.count, title: title, text: "")
            let batch = engine.observe(snapshot, presence: idle ? .idle : .active, policy: on, at: clock.now)
            try store.record(#require(batch))
        }
        try window("Open PR", at: 0)
        try window("Memo draft", at: 30)
        clock.set(start.addingTimeInterval(50 * 60))
        let model = KeyedModel([
            HelperSpec.timeline.brief:
                #"{"items":[{"task":"Review","project":"","first":@Open PR@,"last":@Open PR@,"quote":"PR"},{"task":"Memo","project":"","first":@Memo draft@,"last":@Memo draft@,"quote":"Memo"}]}"#
        ])
        let timeline = HelperModel(
            machine: .test(.timeline, "Timeline"), source: ScreenSource(store: store), store: store,
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: FakeNotifier())
        await timeline.read()
        #expect(timeline.items.map(\.quote) == ["PR"], "the memo window is still open: it waits")
        #expect(model.inputs.withLock { $0.last?.contains("Memo draft") } == false)

        try window("Slides", at: 60)
        clock.set(start.addingTimeInterval(70 * 60))
        await timeline.read()
        #expect(timeline.items.map(\.quote) == ["PR", "Memo"], "the closed memo is read once, the review not again")
        let input = try #require(model.inputs.withLock { $0.last })
        #expect(input.contains("Read before") && !input.contains("Slides"))
    }
}

@Suite struct NotificationsTests {
    @Test func whatWaitedForNotificationsTurnsOnWhenTheAppSeesThemAllowed() async {
        let notifier = FakeNotifier()
        notifier.access = .blocked
        let notifications = Notifications(notifier: notifier)
        let turnedOn = Mutex(0)
        await notifications.whenAllowed { turnedOn.withLock { $0 += 1 } }
        await notifications.whenAllowed { turnedOn.withLock { $0 += 1 } }
        #expect(notifications.blocked && turnedOn.withLock { $0 } == 0)
        await notifications.recheck()
        #expect(notifications.blocked && turnedOn.withLock { $0 } == 0, "still blocked: nothing turns on")
        notifier.access = .allowed
        await notifications.recheck()
        #expect(!notifications.blocked && turnedOn.withLock { $0 } == 2)
        await notifications.recheck()
        #expect(turnedOn.withLock { $0 } == 2, "once")
    }

    @Test func everyMachineOfACrewSharesOneAnswer() throws {
        let store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        #expect(crew.machines.count == 2 && crew.machines.allSatisfy { $0.notifications === crew.notifications })
    }
}
