import Foundation
import Testing

@testable import WorkbenchCore

/// The rules of the one morning notification, and the timers it fires first.
@Suite struct MorningRitualTests {
    private let zone = TimeZone(identifier: "Asia/Kolkata")!
    private let calendar = Calendar.gregorian(in: TimeZone(identifier: "Asia/Kolkata")!)

    private func at(_ hour: Int, _ minute: Int = 0, plusDays days: Int = 0) -> Date {
        let day = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 23 + days, hour: hour, minute: minute))!
        return day
    }

    private func readiness(
        _ now: Date, hour: Int = 9, lastDecided: WorkDay? = nil, presence: PresenceState = .active
    ) -> MorningRitual.Readiness {
        MorningRitual.readiness(now: now, hour: hour, lastDecided: lastDecided, presence: presence, zone: zone)
    }

    private func day(of date: Date) -> WorkDay { WorkDay(containing: date, calendar: calendar) }

    @Test func nothingHappensBeforeTheMorningHourAndTheListIsReadyAtIt() {
        #expect(readiness(at(8, 59)) == .notYet)
        #expect(readiness(at(9)) == .ready)
        #expect(readiness(at(14)) == .ready, "the first active moment after the hour")
    }

    @Test func aSecondDecisionOnOneDayIsSpentAndTheNextDayIsFresh() {
        let decided = day(of: at(9))
        #expect(readiness(at(10), lastDecided: decided) == .spent, "a second morning notification on one day")
        #expect(readiness(at(9, 1, plusDays: 1), lastDecided: decided) == .ready)
    }

    @Test(arguments: [PresenceState.locked, .asleep, .screenOff])
    func noNotificationWhileTheScreenIsLockedOrTheMacAsleep(_ presence: PresenceState) {
        #expect(readiness(at(10), presence: presence) == .away, "a notification while the screen is locked")
    }

    @Test(arguments: [PresenceState.active, .idle])
    func aPersonAtTheMacIsPresent(_ presence: PresenceState) {
        #expect(readiness(at(10), presence: presence) == .ready)
    }

    @Test func twoInTheNightStillBelongsToTheWorkDayThatWasAlreadyDecided() {
        let lastNight = day(of: at(23))
        #expect(readiness(at(2, plusDays: 1), lastDecided: lastNight) == .spent)
    }

    @Test func theNextMorningIsTodaysHourBeforeItAndTomorrowsAfterIt() {
        #expect(MorningRitual.nextMorning(after: at(8), hour: 9, zone: zone) == at(9))
        #expect(MorningRitual.nextMorning(after: at(9), hour: 9, zone: zone) == at(9, plusDays: 1))
        #expect(MorningRitual.nextMorning(after: at(15), hour: 9, zone: zone) == at(9, plusDays: 1))
    }

    @Test func theMessageCountsWhatNeedsThePersonAndIsNilForNothing() {
        #expect(MorningRitual.message(needing: 3) == "3 things need you today")
        #expect(MorningRitual.message(needing: 1) == "1 thing needs you today")
        #expect(MorningRitual.message(needing: 0) == nil)
    }

    @Test func theSettingsStartOffAtNineWithASevenDayCutoff() {
        let settings = MorningSettings()
        #expect(!settings.isOn && settings.hour == 9 && settings.cutoffDays == 7)
        #expect(MorningSettings.hours.contains(settings.hour))
    }

    // MARK: Timers

    @Test func aFiredTimerMakesItsFactSlippedAndACancelledOrSkippedOneDoesNot() async throws {
        let world = try LifecycleWorld()
        try await world.read(
            [pipItem(when: TimeJSON.inDays(1, words: "kal tak"), cite: 1, quote: "bhej dunga")],
            lines: [world.line(1, Days.first, 600, "deck kal tak bhej dunga")])
        let fact = try #require(try world.open().first?.id)
        #expect(try world.store.queries.itemsWithFiredTimers().isEmpty, "not fired yet")
        world.clock.set(Days.second.adding(days: 1).start.addingTimeInterval(3600))
        try world.store.fireTimers()
        #expect(try world.store.queries.itemsWithFiredTimers() == [fact])
        try world.store.close(item: fact, as: "kept", surface: .today)
        #expect(try world.store.queries.itemsWithFiredTimers().isEmpty, "closing cancels the timer")
    }

    @Test func aTimerSkippedAsStaleIsNotAFiredOne() async throws {
        let world = try LifecycleWorld()
        try await world.read(
            [pipItem(when: TimeJSON.inDays(1, words: "kal tak"), cite: 1, quote: "bhej dunga")],
            lines: [world.line(1, Days.first, 600, "deck kal tak bhej dunga")])
        world.clock.set(Days.first.adding(days: 30).start)
        try world.store.fireTimers()
        #expect(try world.store.queries.itemsWithFiredTimers().isEmpty)
    }
}
