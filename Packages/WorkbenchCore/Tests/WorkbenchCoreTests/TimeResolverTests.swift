import Foundation
import Testing

@testable import WorkbenchCore

/// The resolver, on phrases written by hand from the research cases (research 59 F-R6 §1.6). Each fixture is the
/// record a model would fill for the phrase, the line's own time and zone, and the due time in UTC, or none.
@Suite struct TimeResolverTests {
    private static let kolkata = "Asia/Kolkata"
    private static let sundayMorning = "2026-11-22T04:30:00Z"
    private static let wednesdayMorning = "2026-11-18T04:30:00Z"
    private static let fridayMorning = "2026-11-20T04:30:00Z"

    struct Fixture: CustomTestStringConvertible, Sendable {
        var phrase: String
        var record: TimeRecord
        var anchor = TimeResolverTests.sundayMorning
        var zone = TimeResolverTests.kolkata
        var due: String?

        var testDescription: String { phrase }
    }

    private static func future(
        _ offset: Int = 0, weekday: TimeRecord.Weekday = .none, week: TimeRecord.Period = .none,
        part: TimeRecord.PartOfDay = .none, precision: TimeRecord.Precision = .day, ambiguous: Bool = false,
        minutes: Int = 0, dayOfMonth: Int = 0, month: Int = 0, monthWhich: TimeRecord.Period = .none, year: Int = 0,
        hour: Int = TimeRecord.noClockHour, minute: Int = 0, meridiem: TimeRecord.Meridiem = .none
    ) -> TimeRecord {
        TimeRecord(
            direction: .future, precision: precision, offsetDays: offset, offsetMinutes: minutes, weekday: weekday,
            week: week, dayOfMonth: dayOfMonth, month: month, monthWhich: monthWhich, year: year, partOfDay: part,
            clockHour: hour, clockMinute: minute, meridiem: meridiem, ambiguous: ambiguous)
    }

    private static func past(_ offset: Int) -> TimeRecord {
        TimeRecord(direction: .past, precision: .day, offsetDays: offset)
    }

    static let fixtures: [Fixture] = [
        // "kal" and "parson" in both directions: the tense decides, the record carries it.
        Fixture(phrase: "kal tak deck bhej dunga", record: future(1), due: "2026-11-23T18:29:59Z"),
        Fixture(phrase: "kal deck bheja tha", record: past(-1), due: nil),
        Fixture(phrase: "parson tak kar dunga", record: future(2), due: "2026-11-24T18:29:59Z"),
        Fixture(phrase: "parson mila tha", record: past(-2), due: nil),
        Fixture(phrase: "narson tak", record: future(3), due: "2026-11-25T18:29:59Z"),
        Fixture(phrase: "kal milte hain", record: future(1), due: "2026-11-23T18:29:59Z"),
        Fixture(phrase: "kal call hui thi", record: past(-1), due: nil),
        Fixture(phrase: "aaj bheja tha, said in the evening", record: past(0), due: nil),
        Fixture(phrase: "कल तक भेज दूंगा", record: future(1), due: "2026-11-23T18:29:59Z"),
        Fixture(phrase: "दो दिन में", record: future(2), due: "2026-11-24T18:29:59Z"),
        // Part of the day: the owner's hour, never an invented clock time.
        Fixture(
            phrase: "aaj shaam tak", record: future(0, part: .evening, precision: .partOfDay),
            due: "2026-11-22T12:30:00Z"),
        Fixture(
            phrase: "aaj raat tak", record: future(0, part: .night, precision: .partOfDay),
            due: "2026-11-22T15:30:00Z"),
        Fixture(
            phrase: "kal subah", record: future(1, part: .morning, precision: .partOfDay),
            due: "2026-11-23T03:30:00Z"),
        Fixture(
            phrase: "EOD tak bhej deta hun", record: future(0, part: .evening, precision: .partOfDay),
            due: "2026-11-22T12:30:00Z"),
        Fixture(
            phrase: "COB tomorrow", record: future(1, part: .evening, precision: .partOfDay),
            due: "2026-11-23T12:30:00Z"),
        Fixture(
            phrase: "aaj subah tak, said at 10:00", record: future(0, part: .morning, precision: .partOfDay),
            due: nil),
        // Weekdays and weeks, across a week boundary (the week runs Monday to Sunday).
        Fixture(
            phrase: "Friday tak, said on a Sunday", record: future(weekday: .friday, week: .next),
            due: "2026-11-27T18:29:59Z"),
        Fixture(
            phrase: "Friday tak, said on a Wednesday", record: future(weekday: .friday, week: .this),
            anchor: wednesdayMorning, due: "2026-11-20T18:29:59Z"),
        Fixture(
            phrase: "Monday tak, said on a Friday", record: future(weekday: .monday, week: .next),
            anchor: fridayMorning, due: "2026-11-23T18:29:59Z"),
        Fixture(
            phrase: "next Monday, said on a Wednesday", record: future(weekday: .monday, week: .next),
            anchor: wednesdayMorning, due: "2026-11-23T18:29:59Z"),
        Fixture(
            phrase: "this Monday, said on a Wednesday: already gone",
            record: future(weekday: .monday, week: .this), anchor: wednesdayMorning, due: nil),
        Fixture(
            phrase: "agle Monday, said on a Sunday: two readings",
            record: future(weekday: .monday, week: .next, ambiguous: true), due: nil),
        Fixture(
            phrase: "agle hafte tak", record: future(week: .next, precision: .week), due: "2026-11-29T18:29:59Z"),
        Fixture(
            phrase: "is hafte, said on a Wednesday", record: future(week: .this, precision: .week),
            anchor: wednesdayMorning, due: "2026-11-22T18:29:59Z"),
        Fixture(
            phrase: "is hafte, said on the Sunday itself", record: future(week: .this, precision: .week),
            due: "2026-11-22T18:29:59Z"),
        // Days from the line.
        Fixture(phrase: "3 din mein", record: future(3), due: "2026-11-25T18:29:59Z"),
        Fixture(phrase: "2 hafte baad", record: future(14), due: "2026-12-06T18:29:59Z"),
        // Clock changes: the offset of the zone on the due day, not on the line's day.
        Fixture(
            phrase: "kal shaam, said before the clocks go back in New York",
            record: future(1, part: .evening, precision: .partOfDay), anchor: "2026-11-01T00:00:00Z",
            zone: "America/New_York", due: "2026-11-01T23:00:00Z"),
        Fixture(
            phrase: "kal subah, said before the clocks go forward in Berlin",
            record: future(1, part: .morning, precision: .partOfDay), anchor: "2026-03-28T09:00:00Z",
            zone: "Europe/Berlin", due: "2026-03-29T07:00:00Z"),
        Fixture(
            phrase: "aaj tak, said on the day the clocks go forward in Berlin", record: future(0),
            anchor: "2026-03-29T06:00:00Z", zone: "Europe/Berlin", due: "2026-03-29T21:59:59Z"),
        // A line sent after midnight: the record says it is ambiguous, and no date is guessed. Without the flag,
        // the calendar day of the line is the only day code knows.
        Fixture(
            phrase: "kal tak, sent at 01:30: two readings", record: future(1, ambiguous: true),
            anchor: "2026-11-22T20:00:00Z", due: nil),
        Fixture(
            phrase: "kal tak, sent at 01:30, not flagged", record: future(1), anchor: "2026-11-22T20:00:00Z",
            due: "2026-11-24T18:29:59Z"),
        // No time, or no sure time.
        Fixture(
            phrase: "Diwali ke baad dekhte hain", record: TimeRecord(direction: .future, precision: .none), due: nil),
        Fixture(phrase: "no time at all", record: .none, due: nil),
        Fixture(
            phrase: "kal, tense unclear", record: TimeRecord(direction: .unclear, precision: .day, offsetDays: 1),
            due: nil),
        Fixture(
            phrase: "a future record with a negative offset",
            record: TimeRecord(direction: .future, precision: .day, offsetDays: -1),
            due: nil),
        Fixture(phrase: "a date beyond a year", record: future(366), due: nil),

        // Clock hours. A twelve-hour time takes its meridiem from the record or from the part of the day, never from code.
        Fixture(
            phrase: "kal subah 10 baje", record: future(1, part: .morning, precision: .hour, hour: 10),
            due: "2026-11-23T04:30:00Z"),
        Fixture(
            phrase: "kal shaam 5 baje", record: future(1, part: .evening, precision: .hour, hour: 5),
            due: "2026-11-23T11:30:00Z"),
        Fixture(
            phrase: "aaj shaam 6 baje", record: future(0, part: .evening, precision: .hour, hour: 6),
            due: "2026-11-22T12:30:00Z"),
        Fixture(phrase: "5 baje tak: no meridiem, no part of day", record: future(precision: .hour, hour: 5), due: nil),
        Fixture(
            phrase: "5 baje tak: two readings",
            record: future(precision: .hour, ambiguous: true, hour: 5, meridiem: .pm), due: nil),
        Fixture(
            phrase: "5pm today", record: future(precision: .hour, hour: 5, meridiem: .pm), due: "2026-11-22T11:30:00Z"),
        Fixture(
            phrase: "by 17:30 tomorrow", record: future(1, precision: .minute, hour: 17, minute: 30),
            due: "2026-11-23T12:00:00Z"),
        Fixture(
            phrase: "कल सुबह 10:30 बजे", record: future(1, part: .morning, precision: .minute, hour: 10, minute: 30),
            due: "2026-11-23T05:00:00Z"),
        Fixture(
            phrase: "kal raat 11 baje", record: future(1, part: .night, precision: .hour, hour: 11, meridiem: .pm),
            due: "2026-11-23T17:30:00Z"),
        Fixture(
            phrase: "kal raat 11 baje: night alone gives no meridiem",
            record: future(1, part: .night, precision: .hour, hour: 11), due: nil),
        Fixture(
            phrase: "12 baje dopahar", record: future(0, part: .afternoon, precision: .hour, hour: 12),
            due: "2026-11-22T06:30:00Z"),
        Fixture(
            phrase: "kal 12 am", record: future(1, precision: .hour, hour: 12, meridiem: .am),
            due: "2026-11-22T18:30:00Z"),
        Fixture(
            phrase: "aaj 22:00 tak", record: future(0, precision: .hour, hour: 22), due: "2026-11-22T16:30:00Z"),
        Fixture(
            phrase: "aaj subah 9 baje, said at 10:00: already gone",
            record: future(0, part: .morning, precision: .hour, hour: 9), due: nil),
        Fixture(
            phrase: "kal 6 pm, before the clocks go back in New York",
            record: future(1, precision: .hour, hour: 6, meridiem: .pm), anchor: "2026-11-01T00:00:00Z",
            zone: "America/New_York", due: "2026-11-01T23:00:00Z"),
        Fixture(
            phrase: "kal 2:30 am, an hour that does not exist in Berlin that day",
            record: future(1, precision: .minute, hour: 2, minute: 30, meridiem: .am), anchor: "2026-03-28T09:00:00Z",
            zone: "Europe/Berlin", due: nil),
        Fixture(
            phrase: "kal 3 baje dopahar, the day the clocks go forward in Berlin",
            record: future(1, part: .afternoon, precision: .hour, hour: 3), anchor: "2026-03-28T09:00:00Z",
            zone: "Europe/Berlin", due: "2026-03-29T13:00:00Z"),

        // Hours and minutes from the line.
        Fixture(phrase: "2 ghante mein", record: future(precision: .hour, minutes: 120), due: "2026-11-22T06:30:00Z"),
        Fixture(phrase: "in 30 minutes", record: future(precision: .minute, minutes: 30), due: "2026-11-22T05:00:00Z"),
        Fixture(
            phrase: "2 ghante pehle", record: TimeRecord(direction: .past, precision: .hour, offsetMinutes: -120),
            due: nil),
        Fixture(phrase: "90 minute mein, called whole hours", record: future(precision: .hour, minutes: 90), due: nil),
        Fixture(
            phrase: "2 ghante mein, across the clock change in Berlin", record: future(precision: .hour, minutes: 120),
            anchor: "2026-03-29T00:30:00Z", zone: "Europe/Berlin", due: "2026-03-29T02:30:00Z"),

        // A day of the month, and a date.
        Fixture(
            phrase: "30 tareekh tak", record: future(dayOfMonth: 30, monthWhich: .this), due: "2026-11-30T18:29:59Z"),
        Fixture(phrase: "30 तारीख तक", record: future(dayOfMonth: 30, monthWhich: .this), due: "2026-11-30T18:29:59Z"),
        Fixture(
            phrase: "22 tareekh tak: today", record: future(dayOfMonth: 22, monthWhich: .this),
            due: "2026-11-22T18:29:59Z"),
        Fixture(
            phrase: "15 tareekh tak: this month's 15th has passed", record: future(dayOfMonth: 15, monthWhich: .this),
            due: nil),
        Fixture(
            phrase: "agle mahine ki 15 tareekh", record: future(dayOfMonth: 15, monthWhich: .next),
            due: "2026-12-15T18:29:59Z"),
        Fixture(
            phrase: "1 tareekh tak, next month", record: future(dayOfMonth: 1, monthWhich: .next),
            due: "2026-12-01T18:29:59Z"),
        Fixture(
            phrase: "31 tareekh tak: November has 30 days", record: future(dayOfMonth: 31, monthWhich: .this), due: nil),
        Fixture(phrase: "15 Dec tak", record: future(dayOfMonth: 15, month: 12), due: "2026-12-15T18:29:59Z"),
        Fixture(
            phrase: "15 Dec, said on 20 Dec: not moved to next year", record: future(dayOfMonth: 15, month: 12),
            anchor: "2026-12-20T04:30:00Z", due: nil),
        Fixture(
            phrase: "15 Dec 2027, said on 20 Dec", record: future(dayOfMonth: 15, month: 12, year: 2027),
            anchor: "2026-12-20T04:30:00Z", due: "2027-12-15T18:29:59Z"),
        Fixture(phrase: "30 Feb 2027", record: future(dayOfMonth: 30, month: 2, year: 2027), due: nil),
        Fixture(phrase: "29 Feb 2027", record: future(dayOfMonth: 29, month: 2, year: 2027), due: nil),
        Fixture(
            phrase: "29 Feb 2028", record: future(dayOfMonth: 29, month: 2, year: 2028), due: "2028-02-29T18:29:59Z"),
        Fixture(
            phrase: "15 Dec ko 3 baje shaam",
            record: future(part: .evening, precision: .hour, dayOfMonth: 15, month: 12, hour: 3),
            due: "2026-12-15T09:30:00Z"),

        // A month.
        Fixture(
            phrase: "mahine ke end tak", record: future(precision: .month, monthWhich: .this),
            due: "2026-11-30T18:29:59Z"),
        Fixture(
            phrase: "agle mahine tak", record: future(precision: .month, monthWhich: .next), due: "2026-12-31T18:29:59Z"
        ),
        Fixture(phrase: "end of December", record: future(precision: .month, month: 12), due: "2026-12-31T18:29:59Z"),
        Fixture(phrase: "end of March: this year's has passed", record: future(precision: .month, month: 3), due: nil),
        Fixture(
            phrase: "end of March 2027", record: future(precision: .month, month: 3, year: 2027),
            due: "2027-03-31T18:29:59Z"),
        Fixture(
            phrase: "mahine ke end tak, in a leap year", record: future(precision: .month, monthWhich: .this),
            anchor: "2028-02-10T04:30:00Z", due: "2028-02-29T18:29:59Z"),
        Fixture(
            phrase: "end of the month in Berlin, after the clocks go forward",
            record: future(precision: .month, monthWhich: .this), anchor: "2026-03-10T09:00:00Z",
            zone: "Europe/Berlin", due: "2026-03-31T21:59:59Z"),

        // Weekdays with a time, ranges, the end of a week, and what has no date.
        Fixture(
            phrase: "Friday 3 baje shaam, said on a Sunday",
            record: future(weekday: .friday, week: .next, part: .evening, precision: .hour, hour: 3),
            due: "2026-11-27T09:30:00Z"),
        Fixture(
            phrase: "next Monday 9am",
            record: future(weekday: .monday, week: .next, precision: .hour, hour: 9, meridiem: .am),
            due: "2026-11-23T03:30:00Z"),
        Fixture(
            phrase: "Monday se Wednesday ke beech: the due time is the end of the range",
            record: future(weekday: .wednesday, week: .next), due: "2026-11-25T18:29:59Z"),
        Fixture(
            phrase: "EOW tak, said on a Friday", record: future(week: .this, precision: .week), anchor: fridayMorning,
            due: "2026-11-22T18:29:59Z"),
        Fixture(
            phrase: "Q1 ke end tak: no field names a quarter", record: TimeRecord(direction: .future, precision: .none),
            due: nil),
        Fixture(
            phrase: "har Monday: a repeat is not a due time", record: TimeRecord(direction: .future, precision: .none),
            due: nil),
        Fixture(
            phrase: "3 working days: needs a holiday calendar",
            record: TimeRecord(direction: .future, precision: .none), due: nil),
    ]

    private static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    @Test(arguments: fixtures) func theFixtureResolvesAsWritten(_ fixture: Fixture) throws {
        let due = TimeResolver.resolve(
            fixture.record, anchor: Self.instant(fixture.anchor), zone: try #require(TimeZone(identifier: fixture.zone))
        )
        #expect(due.utc == fixture.due.map(Self.instant))
        #expect(due.source == (fixture.due == nil ? .none : .resolved))
        #expect(due.record == fixture.record, "the record is kept, with a date or without")
        #expect(due.zone == fixture.zone && due.precision == fixture.record.precision)
    }

    @Test func thereAreFixturesForEveryClassOfTimeTheResearchNames() {
        #expect(Self.fixtures.count >= 80)
        let precisions = Set(Self.fixtures.map(\.record.precision))
        #expect(precisions == Set(TimeRecord.Precision.allCases), "every precision has a fixture")
        #expect(Self.fixtures.contains { $0.record.dayOfMonth > 0 && $0.record.month > 0 })
        #expect(Self.fixtures.contains { $0.record.dayOfMonth > 0 && $0.record.monthWhich != .none })
        #expect(Self.fixtures.contains { $0.record.offsetMinutes != 0 })
        #expect(Self.fixtures.contains { $0.record.meridiem != .none } && Self.fixtures.contains { $0.record.year > 0 })
    }

    @Test func theSameWordResolvesAgainstTheLineItCameFromNotAgainstNow() throws {
        let zone = try #require(TimeZone(identifier: Self.kolkata))
        let kal = Self.future(1)
        let monday = TimeResolver.resolve(kal, anchor: Self.instant(Self.sundayMorning), zone: zone)
        let friday = TimeResolver.resolve(kal, anchor: Self.instant(Self.fridayMorning), zone: zone)
        #expect(monday.utc == Self.instant("2026-11-23T18:29:59Z"))
        #expect(friday.utc == Self.instant("2026-11-21T18:29:59Z"), "a line sent on Friday means Saturday")
    }

    @Test func theOwnersHoursMoveAPartOfTheDay() throws {
        var hours = DayHours()
        hours.evening = 19
        let due = TimeResolver.resolve(
            Self.future(0, part: .evening, precision: .partOfDay), anchor: Self.instant(Self.sundayMorning),
            zone: try #require(TimeZone(identifier: Self.kolkata)), hours: hours)
        #expect(due.utc == Self.instant("2026-11-22T13:30:00Z"))
    }

    @Test func aTimeRecordIsClosedAndItsPartsAgree() {
        #expect(Self.future(1).isCoherent && TimeRecord.none.isCoherent)
        #expect(Self.future(weekday: .friday, week: .next).isCoherent)
        #expect(!Self.future(2, weekday: .friday, week: .next).isCoherent, "a weekday and a number of days")
        #expect(!Self.future(weekday: .friday).isCoherent, "a weekday needs its week")
        #expect(!Self.future(1, part: .evening).isCoherent, "a part of the day needs its precision")
        #expect(!Self.future(0, precision: .partOfDay).isCoherent, "a precision of part of day needs a part")
        #expect(Self.future(week: .next, precision: .week).isCoherent)
        #expect(!Self.future(1, precision: .week).isCoherent, "a week is not counted in days")
        #expect(!TimeRecord(direction: .future, precision: .none, offsetDays: 1).isCoherent)
        #expect(!TimeRecord(direction: .past, precision: .day, offsetDays: 1).isCoherent)
        #expect(Self.future(365).isCoherent && !Self.future(366).isCoherent)
    }

    @Test func aClockTimeADateAndAMonthAreCoherentOnlyInTheirOwnShapes() {
        typealias Rec = TimeRecord
        let coherent = [
            Self.future(1, part: .morning, precision: .hour, hour: 10),
            Self.future(precision: .minute, hour: 17, minute: 30), Self.future(precision: .hour, minutes: 120),
            Self.future(precision: .minute, minutes: 45), Self.future(dayOfMonth: 30, monthWhich: .this),
            Self.future(dayOfMonth: 15, month: 12, year: 2027), Self.future(precision: .month, monthWhich: .next),
            Self.future(precision: .month, month: 3, year: 2027),
            Self.future(weekday: .friday, week: .next, precision: .hour, hour: 9, meridiem: .am),
        ]
        #expect(coherent.allSatisfy { $0.isCoherent })
        let incoherent = [
            Self.future(precision: .hour),  // an hour with no hour
            Self.future(precision: .hour, hour: 5, minute: 30),  // minutes need the minute precision
            Self.future(precision: .hour, minutes: 90),  // whole hours only
            Self.future(1, precision: .hour, minutes: 60),  // minutes from the line, and a day
            Self.future(precision: .hour, hour: 25), Self.future(precision: .minute, hour: 5, minute: 60),
            Self.future(precision: .hour, hour: 17, meridiem: .pm),  // a meridiem on a 24-hour time
            Self.future(part: .evening, precision: .hour, hour: 5, meridiem: .am),  // am and evening
            Self.future(part: .morning, precision: .hour, hour: 5, meridiem: .pm),
            Self.future(1, precision: .day, hour: 5),  // a clock time needs a clock precision
            Self.future(dayOfMonth: 32, monthWhich: .this), Self.future(dayOfMonth: 5),  // a date needs its month
            Self.future(dayOfMonth: 5, month: 13), Self.future(dayOfMonth: 5, month: 3, monthWhich: .this),
            Self.future(dayOfMonth: 5, monthWhich: .this, year: 2027),  // a year needs a month
            Self.future(dayOfMonth: 5, month: 3, year: 1999), Self.future(2, dayOfMonth: 5, monthWhich: .this),
            Self.future(weekday: .friday, week: .next, dayOfMonth: 5, monthWhich: .this),
            Self.future(precision: .month), Self.future(precision: .month, dayOfMonth: 5, monthWhich: .this),
            Self.future(precision: .month, month: 3, monthWhich: .this),
            Self.future(precision: .month, minutes: 5, monthWhich: .this),
            Self.future(week: .this, precision: .week, month: 3),
        ]
        for (index, record) in incoherent.enumerated() { #expect(!record.isCoherent, "case \(index)") }
    }
}
