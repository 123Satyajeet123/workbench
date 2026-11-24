import Foundation

/// A work day. Night updates sent after midnight still belong to the day before, so a day runs from 05:00 local
/// time to 05:00 the next day.
public struct WorkDay: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// yyyy-MM-dd
    public let description: String
    public let start: Date
    public let end: Date

    public init(containing date: Date, calendar: Calendar = .current) {
        let shifted = date.addingTimeInterval(-Double(RunSettings.standard.dayStartHour) * 3600)
        let midnight = calendar.startOfDay(for: shifted)
        start = calendar.date(byAdding: .hour, value: RunSettings.standard.dayStartHour, to: midnight)!
        end = calendar.date(byAdding: .day, value: 1, to: start)!
        let parts = calendar.dateComponents([.year, .month, .day], from: midnight)
        description = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public init?(_ text: String, calendar: Calendar = .current) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
            let noon = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else { return nil }
        self.init(containing: noon, calendar: calendar)
        guard description == text else { return nil }
    }

    /// The name of the day of the week in English, such as "Sunday": a model cannot count weekdays from a date.
    public var weekdayName: String {
        start.formatted(Date.FormatStyle().weekday(.wide).locale(Locale(identifier: "en_US")))
    }

    public func adding(days: Int, calendar: Calendar = .current) -> WorkDay {
        WorkDay(containing: calendar.date(byAdding: .day, value: days, to: start)!.addingTimeInterval(3600))
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.start < rhs.start }
}
