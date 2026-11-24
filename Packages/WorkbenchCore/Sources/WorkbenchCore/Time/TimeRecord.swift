import Foundation

/// The time a line gives for a fact, as a closed record the model fills. The model never writes a date: code turns the
/// record into an instant (`TimeResolver`). Every part is a closed set or a bounded whole number. A record says the
/// direction of the sentence and a precision, and the precision says which other parts are used:
/// - `day`, `part_of_day`, `hour`, `minute` pick one day: days from the day of the line (`offset_days`), or a weekday of
///   this or the next Monday-to-Sunday week, or a date (`day_of_month` with a `month` or with `month_which`, and an
///   optional `year`).
/// - `part_of_day` adds a part of the day; `hour` and `minute` add a clock time (`clock_hour`, `clock_minute`,
///   `meridiem`) or, with no day, a number of minutes from the line (`offset_minutes`).
/// - `week` names a week (`week`); `month` names a month (`month_which`, or `month` with an optional `year`).
/// - `none` uses no other part.
public struct TimeRecord: Codable, Sendable, Equatable {
    public enum Direction: String, Codable, CaseIterable, Sendable {
        /// The time lies before the line: the sentence says something happened.
        case past
        /// The time lies after the line: the sentence promises or plans.
        case future
        /// The sentence does not say, or two readings fit.
        case unclear
    }

    public enum Weekday: String, Codable, CaseIterable, Sendable {
        case none, monday, tuesday, wednesday, thursday, friday, saturday, sunday

        /// Days after Monday, the first day of the week; nil for none.
        var daysAfterMonday: Int? { Self.allCases.firstIndex(of: self).flatMap { $0 == 0 ? nil : $0 - 1 } }
    }

    /// The week or month that is meant, counted from the line: the one it was sent in, or the one after it.
    public enum Period: String, Codable, CaseIterable, Sendable {
        case none, this, next
    }

    public enum PartOfDay: String, Codable, CaseIterable, Sendable {
        case none, morning, afternoon, evening, night
    }

    /// Whether a clock time of twelve hours is before or after noon. Never guessed by code.
    public enum Meridiem: String, Codable, CaseIterable, Sendable {
        case none, am, pm
    }

    public enum Precision: String, Codable, CaseIterable, Sendable {
        /// A clock time on the hour, or a whole number of hours from the line.
        case hour
        /// A clock time with minutes, or minutes from the line.
        case minute
        case partOfDay = "part_of_day"
        case day
        case week
        case month
        /// The line states no time that a date can be worked out from.
        case none
    }

    public static let noClockHour = -1

    public var direction: Direction
    public var precision: Precision
    /// Whole days from the calendar day the line was sent, negative for the past.
    public var offsetDays: Int
    /// Whole minutes from the line, negative for the past: "2 ghante mein" is 120.
    public var offsetMinutes: Int
    public var weekday: Weekday
    public var week: Period
    /// 1 to 31, or 0 for none.
    public var dayOfMonth: Int
    /// 1 to 12, or 0 for none.
    public var month: Int
    /// The month a date or a month deadline is in, when `month` is not given.
    public var monthWhich: Period
    /// A year from 2000 to 2100, or 0 for none: then the year of the line.
    public var year: Int
    public var partOfDay: PartOfDay
    /// The hour as the line writes it, 0 to 23, or -1 for none.
    public var clockHour: Int
    public var clockMinute: Int
    public var meridiem: Meridiem
    /// The model sees two readings that differ in the date, such as a line sent in the small hours that says "kal".
    public var ambiguous: Bool

    enum CodingKeys: String, CodingKey {
        case direction, precision, weekday, week, month, year, meridiem, ambiguous
        case offsetDays = "offset_days"
        case offsetMinutes = "offset_minutes"
        case dayOfMonth = "day_of_month"
        case monthWhich = "month_which"
        case partOfDay = "part_of_day"
        case clockHour = "clock_hour"
        case clockMinute = "clock_minute"
    }

    public init(
        direction: Direction, precision: Precision, offsetDays: Int = 0, offsetMinutes: Int = 0,
        weekday: Weekday = .none, week: Period = .none, dayOfMonth: Int = 0, month: Int = 0,
        monthWhich: Period = .none, year: Int = 0, partOfDay: PartOfDay = .none, clockHour: Int = noClockHour,
        clockMinute: Int = 0, meridiem: Meridiem = .none, ambiguous: Bool = false
    ) {
        self.direction = direction
        self.precision = precision
        self.offsetDays = offsetDays
        self.offsetMinutes = offsetMinutes
        self.weekday = weekday
        self.week = week
        self.dayOfMonth = dayOfMonth
        self.month = month
        self.monthWhich = monthWhich
        self.year = year
        self.partOfDay = partOfDay
        self.clockHour = clockHour
        self.clockMinute = clockMinute
        self.meridiem = meridiem
        self.ambiguous = ambiguous
    }

    /// A line that states no time.
    public static let none = TimeRecord(direction: .unclear, precision: .none)

    /// Whether the parts agree with each other: every number is in its bounds, the direction fits the signs, and the
    /// precision uses exactly the parts it needs. A record that fails is refused by the verifier, so every record that
    /// passes is one that code can resolve or knows it cannot.
    public var isCoherent: Bool {
        guard isInBounds, signsFitDirection else { return false }
        switch precision {
        case .none: return usesNothing
        case .week: return week != .none && onlyWeek
        case .month: return onlyMonth
        case .day: return selectsOneDay && noClock && partOfDay == .none
        case .partOfDay: return selectsOneDay && noClock && partOfDay != .none
        case .hour, .minute: return isClockPrecisionCoherent
        }
    }

    private var isInBounds: Bool {
        abs(offsetDays) <= RunSettings.standard.timeOffsetDays
            && abs(offsetMinutes) <= RunSettings.standard.timeOffsetMinutes
            && (0...31).contains(dayOfMonth) && (0...12).contains(month)
            && (year == 0 || RunSettings.standard.timeYears.contains(year))
            && (Self.noClockHour...23).contains(clockHour) && (0...59).contains(clockMinute)
    }

    private var signsFitDirection: Bool {
        switch direction {
        case .future: offsetDays >= 0 && offsetMinutes >= 0
        case .past: offsetDays <= 0 && offsetMinutes <= 0
        case .unclear: true
        }
    }

    private var noDay: Bool {
        offsetDays == 0 && weekday == .none && week == .none && dayOfMonth == 0 && month == 0 && monthWhich == .none
            && year == 0
    }
    private var noClock: Bool {
        offsetMinutes == 0 && clockHour == Self.noClockHour && clockMinute == 0 && meridiem == .none
    }
    private var usesNothing: Bool { noDay && noClock && partOfDay == .none }
    private var onlyWeek: Bool {
        offsetDays == 0 && weekday == .none && dayOfMonth == 0 && month == 0 && monthWhich == .none && year == 0
            && noClock && partOfDay == .none
    }
    private var onlyMonth: Bool {
        offsetDays == 0 && weekday == .none && week == .none && dayOfMonth == 0 && noClock && partOfDay == .none
            && selectsMonth
    }

    /// A month is named by `month` (with an optional year) or by `month_which`, and not both.
    private var selectsMonth: Bool {
        month == 0 ? monthWhich != .none && year == 0 : monthWhich == .none
    }

    /// Exactly one way of naming a day: days from the line, a weekday of a week, or a date.
    private var selectsOneDay: Bool {
        if dayOfMonth > 0 { return selectsMonth && offsetDays == 0 && weekday == .none && week == .none }
        if weekday != .none { return week != .none && offsetDays == 0 && noMonth }
        return week == .none && noMonth
    }

    private var noMonth: Bool { month == 0 && monthWhich == .none && year == 0 }

    /// A clock time on a day, or minutes from the line with no day.
    private var isClockPrecisionCoherent: Bool {
        if offsetMinutes != 0 {
            return noDay && offsetDays == 0 && clockHour == Self.noClockHour && clockMinute == 0 && meridiem == .none
                && partOfDay == .none && (precision == .minute || offsetMinutes % 60 == 0)
        }
        guard clockHour != Self.noClockHour, selectsOneDay else { return false }
        return (precision == .minute || clockMinute == 0) && isMeridiemCoherent
    }

    /// A meridiem belongs to an hour of twelve, and does not contradict the part of the day.
    private var isMeridiemCoherent: Bool {
        guard meridiem != .none else { return true }
        let afterNoon = [PartOfDay.afternoon, .evening, .night]
        return (1...12).contains(clockHour)
            && (partOfDay == .none
                || (meridiem == .am) == (partOfDay == .morning) && (meridiem == .pm) == afterNoon.contains(partOfDay))
    }
}

/// What the model gives for a time: the record, and the words of the line that state it.
public struct TimeMention: Decodable, Sendable, Equatable {
    public var record: TimeRecord
    /// Empty when the line states no time; else words of the cited line.
    public var words: String

    enum CodingKeys: String, CodingKey { case words }

    public init(record: TimeRecord, words: String) {
        self.record = record
        self.words = words
    }

    public init(from decoder: any Decoder) throws {
        record = try TimeRecord(from: decoder)
        words = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .words)
    }

    /// The mention in a reply, or nil when the value is not an object that is exactly this record.
    public init?(_ value: JSONValue) {
        guard let data = try? JSONEncoder().encode(value),
            let mention = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = mention
    }

    /// The reply schema of a time field: every part is required, each from its closed set.
    public static var schema: JSONSchema {
        .object([
            .init("direction", .choice(TimeRecord.Direction.self)),
            .init("precision", .choice(TimeRecord.Precision.self)),
            .init("offset_days", .integer), .init("offset_minutes", .integer),
            .init("weekday", .choice(TimeRecord.Weekday.self)), .init("week", .choice(TimeRecord.Period.self)),
            .init("day_of_month", .integer), .init("month", .integer),
            .init("month_which", .choice(TimeRecord.Period.self)), .init("year", .integer),
            .init("part_of_day", .choice(TimeRecord.PartOfDay.self)), .init("clock_hour", .integer),
            .init("clock_minute", .integer), .init("meridiem", .choice(TimeRecord.Meridiem.self)),
            .init("ambiguous", .boolean), .init("words", .string),
        ])
    }
}
