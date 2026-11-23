import CaptureService
import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// A presence a test sets.
private final class FakePresence: PresenceSource {
    private let current = Mutex(PresenceState.active)
    var state: PresenceState {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }
    func state(idleAfter: TimeInterval) -> PresenceState { state }
}

/// A count a test sets.
private final class Needs: Sendable {
    private let current: Mutex<Int>
    init(_ count: Int) { current = Mutex(count) }
    var count: Int {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }
}

/// Whether the notification gate takes a post, which a test sets.
private final class Gate: Sendable {
    private let open = Mutex(true)
    var isOpen: Bool {
        get { open.withLock { $0 } }
        set { open.withLock { $0 = newValue } }
    }
}

/// Posts straight through the notifier, so the other tests do not depend on the gate.
private func direct(_ notifications: Notifications, _ title: String) async -> Bool {
    (try? await notifications.notifier.post(title: title, body: "", page: .mochi)) != nil
}

/// The morning notification over a store, a clock, a presence and a count of what needs the person.
@Suite struct MorningScheduleTests {
    private let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 7))!

    private func at(_ hour: Int, plusDays days: Int = 0) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: monday)!.addingTimeInterval(Double(hour - 7) * 3600)
    }

    private struct Setup {
        let schedule: MorningSchedule
        let notifier: FakeNotifier
        let notifications: Notifications
        let clock: TestClock
        let presence: FakePresence
        let store: Store
        let needs: Needs
        let gate: Gate
    }

    private func setup(count: Int = 3, on: Bool = true) async throws -> Setup {
        let clock = TestClock(monday)
        let store = try scratchStore(clock: { clock.now })
        let notifier = FakeNotifier()
        let presence = FakePresence()
        let needs = Needs(count)
        let gate = Gate()
        let notifications = Notifications(notifier: notifier)
        let schedule = MorningSchedule(
            store: store, notifications: notifications, presence: presence, needsCount: { needs.count },
            notify: { gate.isOpen ? await direct(notifications, $0) : false })
        if on { await schedule.setOn(true) }
        return Setup(
            schedule: schedule, notifier: notifier, notifications: notifications, clock: clock, presence: presence,
            store: store, needs: needs, gate: gate)
    }

    @Test func itIsOffUntilTheFounderTurnsItOnAndThenNothingComesBeforeTheHour() async throws {
        let off = try await setup(on: false)
        off.clock.set(at(10))
        await off.schedule.check()
        #expect(off.notifier.posted.isEmpty, "off by default")
        let on = try await setup()
        on.clock.set(at(8))
        await on.schedule.check()
        #expect(on.notifier.posted.isEmpty, "before the morning hour")
    }

    @Test func atTheHourItPostsOneNotificationThatOpensToday() async throws {
        let day = try await setup()
        day.clock.set(at(9))
        await day.schedule.check()
        #expect(day.notifier.posted.map(\.title) == ["3 things need you today"])
        #expect(day.notifier.posted.map(\.page) == [.mochi], "a click opens the list")
    }

    @Test func aSecondMorningNotificationOnOneDayNeverComesAndTheNextDayHasOne() async throws {
        let day = try await setup()
        day.clock.set(at(9))
        await day.schedule.check()
        day.clock.set(at(11))
        await day.schedule.check()
        await day.schedule.check()
        #expect(day.notifier.posted.count == 1)
        day.clock.set(at(9, plusDays: 1))
        await day.schedule.check()
        #expect(day.notifier.posted.count == 2)
    }

    @Test(arguments: [PresenceState.locked, .asleep, .screenOff])
    func noNotificationWhileAwayAndOneAtTheFirstActiveMomentAfter(_ away: PresenceState) async throws {
        let day = try await setup()
        day.presence.state = away
        day.clock.set(at(9))
        await day.schedule.check()
        #expect(day.notifier.posted.isEmpty, "a notification while the screen is locked")
        day.clock.set(at(10))
        day.presence.state = .active
        await day.schedule.check()
        #expect(day.notifier.posted.count == 1)
    }

    @Test func nothingThatNeedsThePersonIsSilenceAndSpendsTheDay() async throws {
        let day = try await setup(count: 0)
        day.clock.set(at(9))
        await day.schedule.check()
        day.needs.count = 2
        day.clock.set(at(10))
        await day.schedule.check()
        #expect(day.notifier.posted.isEmpty)
    }

    @Test func aSummaryTheGateDoesNotPostLeavesTheDayOpenForTheNextWake() async throws {
        let day = try await setup()
        day.gate.isOpen = false
        day.clock.set(at(9))
        await day.schedule.check()
        #expect(day.notifier.posted.isEmpty)
        day.gate.isOpen = true
        day.clock.set(at(10))
        await day.schedule.check()
        #expect(day.notifier.posted.count == 1)
    }

    @Test func oneThingReadsInTheSingular() async throws {
        let day = try await setup(count: 1)
        day.clock.set(at(9))
        await day.schedule.check()
        #expect(day.notifier.posted.map(\.title) == ["1 thing needs you today"])
    }

    @Test func theHourTheFounderSetsDecidesWhenItComes() async throws {
        let day = try await setup()
        day.schedule.settings.hour = 11
        day.clock.set(at(10))
        await day.schedule.check()
        #expect(day.notifier.posted.isEmpty)
        day.clock.set(at(11))
        await day.schedule.check()
        #expect(day.notifier.posted.count == 1)
    }

    @Test func blockedNotificationsKeepItOffUntilMacOSAllowsThem() async throws {
        let day = try await setup(on: false)
        day.notifier.access = .blocked
        await day.schedule.setOn(true)
        #expect(!day.schedule.settings.isOn)
        day.notifier.access = .allowed
        await day.notifications.recheck()
        #expect(day.schedule.settings.isOn)
    }

    @Test func theSettingsSurviveARestart() async throws {
        let day = try await setup()
        day.schedule.settings.hour = 7
        day.schedule.settings.cutoffDays = 14
        let again = MorningSchedule(
            store: day.store, notifications: day.notifications, needsCount: { 0 }, notify: { _ in true })
        #expect(again.settings.isOn && again.settings.hour == 7 && again.settings.cutoffDays == 14)
    }

    @Test func theScheduleWakesAtTheNextMorningHourAndNeverWhileOff() async throws {
        let day = try await setup()
        #expect(day.schedule.nextWake(after: at(8)) == at(9))
        #expect(day.schedule.nextWake(after: at(10)) == at(9, plusDays: 1))
        await day.schedule.setOn(false)
        #expect(day.schedule.nextWake(after: at(8)) == nil)
    }

    // MARK: Timers

    @Test func theCheckFiresTheDueTimersBeforeItCountsSoSlippedFactsAreCurrent() async throws {
        let clock = TestClock(monday)
        let store = try scratchStore(clock: { clock.now })
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Asha" }, notifier: FakeNotifier())
        try await TodaySample.populate(store: store, crew: crew)
        let model = TodayModel(store: store, crew: crew, me: { "Asha" })
        let notifier = FakeNotifier()
        let notifications = Notifications(notifier: notifier)
        let schedule = MorningSchedule(
            store: store, notifications: notifications, presence: FakePresence(),
            needsCount: {
                model.refresh()
                return model.needsCount
            },
            notify: { await direct(notifications, $0) })
        await schedule.setOn(true)
        #expect(try store.queries.itemsWithFiredTimers().isEmpty)
        clock.set(at(9, plusDays: 1))
        await schedule.check()
        let fired = try store.queries.itemsWithFiredTimers()
        #expect(!fired.isEmpty, "fireTimers ran in the same check")
        #expect(notifier.posted.count == 1)
    }
}

/// The morning schedule over the real notification gate, with its daily cap and quiet hours.
@Suite struct MorningScheduleGateTests {
    private let seven = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 7))!

    private func at(_ hour: Int) -> Date { seven.addingTimeInterval(Double(hour - 7) * 3600) }

    private func setup() async throws -> (MorningSchedule, FakeNotifier, TestClock) {
        let clock = TestClock(seven)
        let store = try scratchStore(clock: { clock.now })
        let notifier = FakeNotifier()
        let defaults = UserDefaults(suiteName: "morning-gate-\(UUID().uuidString)")!
        let notifications = Notifications(
            notifier: notifier, defaults: defaults, clock: { clock.now }, windowInFront: { false })
        let schedule = MorningSchedule(
            store: store, notifications: notifications, presence: FakePresence(), needsCount: { 3 },
            notify: { (try? await notifications.notifySummary(title: $0, body: "Open Today", page: .mochi)) == true })
        await schedule.setOn(true)
        schedule.settings.hour = 7
        return (schedule, notifier, clock)
    }

    @Test func theGatePostsTheSummaryOnceAndTheDayIsHandled() async throws {
        let (schedule, notifier, clock) = try await setup()
        clock.set(at(9))
        await schedule.check()
        await schedule.check()
        #expect(notifier.posted.map(\.title) == ["3 things need you today"])
        #expect(notifier.posted.map(\.page) == [.mochi])
    }

    @Test func theGateRefusingInQuietHoursLeavesTheDayOpenForTheNextWake() async throws {
        let (schedule, notifier, clock) = try await setup()
        clock.set(at(7))
        await schedule.check()
        #expect(notifier.posted.isEmpty, "quiet hours run until 08:00")
        clock.set(at(8))
        await schedule.check()
        #expect(notifier.posted.count == 1)
    }
}
