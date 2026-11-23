import Foundation

/// When a fact is due, and how code came to know. The instant is UTC; the zone is the owner's zone at the line, kept
/// so that a later change of rules cannot move the due time without notice.
public struct Due: Codable, Sendable, Equatable {
    public enum Source: String, Codable, CaseIterable, Sendable {
        /// A person typed the day.
        case stated
        /// Code worked it out from a time record and the line's own time.
        case resolved
        /// No time was given, and a policy set one.
        case `default`
        /// No due time: the line gave none, the record is ambiguous, or the words are about the past.
        case none
    }

    public var utc: Date?
    public var zone: String
    public var source: Source
    public var precision: TimeRecord.Precision
    /// The record the model filled, kept even when it gave no date. Nil for a day a person typed.
    public var record: TimeRecord?
    /// True when the zone is the owner's zone at a migration, not the zone the day was set in. Absent otherwise.
    public var zoneAssumed: Bool?

    public init(
        utc: Date?, zone: String, source: Source, precision: TimeRecord.Precision, record: TimeRecord? = nil
    ) {
        self.utc = utc
        self.zone = zone
        self.source = source
        self.precision = precision
        self.record = record
    }

    /// The calendar of the zone the due time was set in.
    public var calendar: Calendar { Calendar.gregorian(in: TimeZone(identifier: zone) ?? .gmt) }

    /// The work day the due time falls on in the zone it was set in, as a day of this Mac's calendar: a due on Friday
    /// is Friday wherever the owner is. Nil when there is no due time.
    public var day: WorkDay? { utc.flatMap { WorkDay(WorkDay(containing: $0, calendar: calendar).description) } }

    /// No due time, with the record that gave none kept.
    public static func unresolved(_ record: TimeRecord, zone: TimeZone) -> Due {
        Due(utc: nil, zone: zone.identifier, source: .none, precision: record.precision, record: record)
    }

    /// A day a person typed: due at the end of it, in the zone of this Mac.
    public static func stated(on day: WorkDay, zone: TimeZone = .current) -> Due {
        let calendar = Calendar.gregorian(in: zone)
        return Due(
            utc: calendar.endOfDay(of: day.start), zone: zone.identifier, source: .stated, precision: .day)
    }
}

extension Calendar {
    /// A Gregorian calendar in `zone` whose week runs Monday to Sunday, whatever the region setting.
    static func gregorian(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// The last second of the day that holds `date`.
    func endOfDay(of date: Date) -> Date? { self.date(bySettingHour: 23, minute: 59, second: 59, of: date) }
}
