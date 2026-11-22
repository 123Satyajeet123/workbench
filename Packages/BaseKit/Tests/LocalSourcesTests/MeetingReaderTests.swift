import Foundation
import Testing
import WorkbenchCore

@testable import LocalSources

/// A calendar of fixed events that counts every ask, so a test can see that nothing was read.
final class FakeCalendar: CalendarEvents, @unchecked Sendable {
    var access = SystemAccess.allowed
    var events: [Meeting]
    private(set) var accessAsks = 0
    private(set) var reads: [[String]] = []

    init(_ events: [Meeting] = []) { self.events = events }

    func requestAccess() async -> SystemAccess {
        accessAsks += 1
        return access
    }

    func calendars() -> [CalendarInfo] {
        [CalendarInfo(id: "work", title: "Work"), CalendarInfo(id: "home", title: "Home")]
    }

    func meetings(during interval: DateInterval, in calendarIDs: [String]) -> [Meeting] {
        reads.append(calendarIDs)
        return events.filter { calendarIDs.contains($0.calendar) && interval.contains($0.start) }
    }
}

@Suite struct MeetingReaderTests {
    private let noon = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!

    private func meeting(_ title: String, in calendar: String, at hour: Int) -> Meeting {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: noon)!
        return Meeting(id: title, calendar: calendar, title: title, start: start, end: start.addingTimeInterval(1800))
    }

    private func reader(_ fake: FakeCalendar, _ policy: CapturePolicy) -> MeetingReader {
        MeetingReader(calendar: fake, policy: FixedPolicy(policy: policy))
    }

    private let on = CapturePolicy(switches: [.calendar: true])

    @Test func withTheConsentOffNothingIsAskedOrRead() async throws {
        let fake = FakeCalendar([meeting("Sync", in: "work", at: 9)])
        await #expect(throws: ReadError.denied(.sourceSwitchedOff)) {
            _ = try await reader(fake, CapturePolicy()).today(at: noon)
        }
        #expect(fake.accessAsks == 0 && fake.reads.isEmpty)
    }

    @Test func refusedAccessIsReportedAndNothingIsRead() async throws {
        let fake = FakeCalendar([meeting("Sync", in: "work", at: 9)])
        fake.access = .blocked
        await #expect(throws: CalendarError.accessRefused(.blocked)) { _ = try await reader(fake, on).today(at: noon) }
        #expect(fake.reads.isEmpty)
    }

    @Test func everyCalendarIsReadUntilTheyAreChosen() async throws {
        let fake = FakeCalendar([meeting("Sync", in: "work", at: 9), meeting("Dentist", in: "home", at: 10)])
        let day = try await reader(fake, on).today(at: noon)
        #expect(day.meetings.map(\.title) == ["Sync", "Dentist"])
        #expect(day.calendars.map(\.id) == ["work", "home"])
    }

    @Test func onlyTheChosenCalendarsAreRead() async throws {
        let fake = FakeCalendar([meeting("Sync", in: "work", at: 9), meeting("Dentist", in: "home", at: 10)])
        let chosen = CapturePolicy(switches: [.calendar: true], allowList: [.calendar: ["work"]])
        let day = try await reader(fake, chosen).today(at: noon)
        #expect(day.meetings.map(\.title) == ["Sync"])
        #expect(fake.reads == [["work"]])
        #expect(day.calendars.count == 2)
    }

    @Test func aPausedCaptureReadsNothing() async throws {
        let fake = FakeCalendar([meeting("Sync", in: "work", at: 9)])
        let paused = CapturePolicy(mode: .paused(until: noon.addingTimeInterval(60)), switches: [.calendar: true])
        await #expect(throws: ReadError.denied(.paused)) { _ = try await reader(fake, paused).today(at: noon) }
        #expect(fake.reads.isEmpty)
    }

    @Test func onlyTodaysMeetingsAreAsked() async throws {
        let tomorrow = meeting("Later", in: "work", at: 9).start.addingTimeInterval(86_400)
        var later = meeting("Later", in: "work", at: 9)
        later.start = tomorrow
        let day = try await reader(FakeCalendar([later, meeting("Sync", in: "work", at: 9)]), on).today(at: noon)
        #expect(day.meetings.map(\.title) == ["Sync"])
    }
}
