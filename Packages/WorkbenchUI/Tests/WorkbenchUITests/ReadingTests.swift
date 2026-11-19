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
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: HelperSpec.team.task, founder: { "Kabir" },
            container: container)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        let model = KeyedModel(["team ledger": reply])
        let notifier = FakeNotifier()
        let pip = HelperModel(
            machine: .test(.team, "Pip"), source: .whatsapp(source), store: store,
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: notifier)
        return Setup(pip: pip, model: model, notifier: notifier, container: container, clock: clock, store: store)
    }

    @Test func aSecondReadingSendsOnlyNewLinesAndNeverReReadsOrDuplicates() async throws {
        let s = try setup(
            reply:
                #"{"items":[{"person":"Asha","kind":"done","text":"Login API","eta":"","cite":11,"quote":"login API done"}]}"#
        )
        await s.pip.read()
        #expect(s.pip.items.count == 1)

        await s.pip.read()
        #expect(s.pip.phase == .upToDate)
        #expect(s.model.calls.withLock { $0 } == 1, "nothing new, no call")

        try addMessage(30, "payments blocked on keys", at: noon.addingTimeInterval(600), to: s.container)
        s.model.replies.withLock {
            $0["team ledger"] =
                #"{"items":[{"person":"Asha","kind":"done","text":"Login API reworded","eta":"","cite":11,"quote":"login API done"},{"person":"Asha","kind":"blocker","text":"Payments blocked","eta":"","cite":30,"quote":"payments blocked on keys"}]}"#
        }
        await s.pip.read()
        #expect(s.pip.phase == .read(kept: 1, dropped: 1), "a line read before cannot be cited again")
        #expect(s.pip.items.map(\.quote) == ["login API done", "payments blocked on keys"])
    }

    @Test func readingThroughTheDayAlertsOnlyForNewBlockersAndOnlyInsideItsHours() async throws {
        let s = try setup(
            reply:
                #"{"items":[{"person":"Asha","kind":"blocker","text":"Waiting for keys","eta":"","cite":11,"quote":"login API done"},{"person":"Asha","kind":"done","text":"Login API","eta":"","cite":11,"quote":"login API"}]}"#
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
