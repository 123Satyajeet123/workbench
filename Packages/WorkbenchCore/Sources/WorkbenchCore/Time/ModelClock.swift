import Foundation

/// The one clock the model reads: 24-hour "HH:mm" in the given zone, in a fixed locale.
/// The person's locale never changes it, so "17:40" is never read as "05:40".
public enum ModelClock {
    public static func time(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
                locale: Locale(identifier: "en_US_POSIX"), timeZone: zone, calendar: .gregorian(in: zone)))
    }
}
