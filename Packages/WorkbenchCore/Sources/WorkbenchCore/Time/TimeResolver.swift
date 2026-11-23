import Foundation

/// The hour, in the owner's zone, that a part of the day stands for when a line names no clock time. These are
/// conventions, not measured; the owner may change them (research 59, F-R6 §1.5).
public struct DayHours: Codable, Sendable, Equatable {
    public var morning = 9
    public var afternoon = 13
    public var evening = 18
    public var night = 21

    public init() {}

    func hour(of part: TimeRecord.PartOfDay) -> Int? {
        switch part {
        case .none: nil
        case .morning: morning
        case .afternoon: afternoon
        case .evening: evening
        case .night: night
        }
    }
}

/// Turns a time record into a due time. A pure function of the record, the time of the line it came from and the
/// owner's zone: never of the clock now, so a line read a week late resolves against the day it was sent. Only a
/// coherent, unambiguous record about the future gives a time. Any other record, and any record whose date does not
/// exist, whose date has passed, whose hour has no meridiem or falls in a clock change gap, gives none, and never a
/// guessed date. Code does calendar maths only: it reads no words.
public enum TimeResolver {
    public static func resolve(
        _ record: TimeRecord, anchor: Date, zone: TimeZone, hours: DayHours = DayHours()
    ) -> Due {
        let none = Due.unresolved(record, zone: zone)
        guard record.direction == .future, !record.ambiguous, record.precision != .none, record.isCoherent else {
            return none
        }
        let calendar = Calendar.gregorian(in: zone)
        guard let due = instant(of: record, anchor: anchor, hours: hours, calendar: calendar), due > anchor else {
            return none
        }
        return Due(utc: due, zone: zone.identifier, source: .resolved, precision: record.precision, record: record)
    }

    private static func instant(of record: TimeRecord, anchor: Date, hours: DayHours, calendar: Calendar) -> Date? {
        if record.offsetMinutes != 0 { return anchor.addingTimeInterval(Double(record.offsetMinutes) * 60) }
        guard let day = day(of: record, anchor: anchor, calendar: calendar) else { return nil }
        switch record.precision {
        case .hour, .minute:
            guard let hour = clockHour(of: record) else { return nil }
            return calendar.date(
                bySettingHour: hour, minute: record.clockMinute, second: 0, of: day, matchingPolicy: .strict
            ).flatMap { calendar.isDate($0, inSameDayAs: day) ? $0 : nil }
        case .partOfDay:
            return hours.hour(of: record.partOfDay).flatMap {
                calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day, matchingPolicy: .nextTime)
            }
        case .day, .week, .month, .none:
            return calendar.endOfDay(of: day)
        }
    }

    /// The hour on a 24-hour clock. An hour of twelve takes its meridiem from the record, or from the part of the day
    /// when that says before or after noon; with neither it has none, and the time is unknown.
    private static func clockHour(of record: TimeRecord) -> Int? {
        let hour = record.clockHour
        guard (1...12).contains(hour) else { return hour }
        let afterNoon: Bool
        switch (record.meridiem, record.partOfDay) {
        case (.pm, _), (.none, .afternoon), (.none, .evening): afterNoon = true
        case (.am, _), (.none, .morning): afterNoon = false
        case (.none, .night), (.none, .none): return nil
        }
        return hour % 12 + (afterNoon ? 12 : 0)
    }

    /// Midnight of the day the record names, or nil when that day does not exist. A date is never moved to another
    /// month or year unless the record says so: a day that has passed is found as it is, and `resolve` then finds its
    /// end before the line and gives no due time.
    private static func day(of record: TimeRecord, anchor: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: anchor)
        switch record.precision {
        case .month: return lastDay(ofMonthIn: record, today: today, calendar: calendar)
        case .week: return weekday(of: record, anchor: anchor, calendar: calendar)
        default:
            if record.dayOfMonth > 0 { return date(of: record, today: today, calendar: calendar) }
            if record.weekday != .none { return weekday(of: record, anchor: anchor, calendar: calendar) }
            return calendar.date(byAdding: .day, value: record.offsetDays, to: today)
        }
    }

    /// A weekday of the week of the anchor or the one after it, counted Monday to Sunday; a whole week stands for its
    /// Sunday.
    private static func weekday(of record: TimeRecord, anchor: Date, calendar: Calendar) -> Date? {
        let sunday = 6
        let inWeek = record.weekday.daysAfterMonday ?? sunday
        let weeksAhead = record.week == .next ? 1 : 0
        guard let monday = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start else { return nil }
        return calendar.date(byAdding: .day, value: weeksAhead * 7 + inWeek, to: monday)
    }

    /// The first day of the month the record names: the month of the line or the next, or the given month of the given
    /// year (the year of the line when none is given).
    private static func firstOfMonth(of record: TimeRecord, today: Date, calendar: Calendar) -> Date? {
        let now = calendar.dateComponents([.year, .month], from: today)
        if record.month > 0 {
            return calendar.date(
                from: DateComponents(year: record.year > 0 ? record.year : now.year, month: record.month, day: 1))
        }
        guard let thisMonth = calendar.date(from: DateComponents(year: now.year, month: now.month, day: 1)) else {
            return nil
        }
        return record.monthWhich == .next ? calendar.date(byAdding: .month, value: 1, to: thisMonth) : thisMonth
    }

    private static func lastDay(ofMonthIn record: TimeRecord, today: Date, calendar: Calendar) -> Date? {
        guard let first = firstOfMonth(of: record, today: today, calendar: calendar),
            let days = calendar.range(of: .day, in: .month, for: first)?.count
        else { return nil }
        return calendar.date(byAdding: .day, value: days - 1, to: first)
    }

    /// The date `day_of_month` in the month the record names, or nil when the month has no such day.
    private static func date(of record: TimeRecord, today: Date, calendar: Calendar) -> Date? {
        guard let first = firstOfMonth(of: record, today: today, calendar: calendar),
            calendar.range(of: .day, in: .month, for: first)?.contains(record.dayOfMonth) == true
        else { return nil }
        return calendar.date(byAdding: .day, value: record.dayOfMonth - 1, to: first)
    }
}
