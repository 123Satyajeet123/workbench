import Foundation
import Lines

/// The time of a message as the WhatsApp Web page stamps it: `3:45 PM, 11/22/2026` or `15:45, 22/11/2026`. The page
/// does not say whether the day or the month comes first. A batch of stamps settles it when one stamp has a part
/// above 12; a stamp whose two parts differ and that no stamp settles has no time. A wrong day is worse than none.
enum WebSentStamp {
    private struct Parts {
        var hour: Int
        var minute: Int
        var first: Int
        var second: Int
        var year: Int
    }

    /// The instant of each stamp, in the time zone of the browser, or nil where it cannot be told.
    static func instants(_ stamps: [String?], in zone: TimeZone) -> [UTCInstant?] {
        let parts = stamps.map { $0.flatMap(parse) }
        let order = dateOrder(of: parts.compactMap { $0 })
        return parts.map { $0.flatMap { instant(of: $0, order: order, in: zone) } }
    }

    private enum DateOrder { case dayFirst, monthFirst, unknown }

    private static func parse(_ stamp: String) -> Parts? {
        guard
            let match = stamp.wholeMatch(
                of: #/(\d{1,2}):(\d{2})(?::\d{2})?(?:\s?([AaPp])[Mm])?,\s*(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})/#),
            var hour = Int(match.1), let minute = Int(match.2),
            let first = Int(match.4), let second = Int(match.5), let year = Int(match.6)
        else { return nil }
        if let marker = match.3 {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (marker.lowercased() == "p" ? 12 : 0)
        }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return Parts(hour: hour, minute: minute, first: first, second: second, year: year)
    }

    private static func dateOrder(of parts: [Parts]) -> DateOrder {
        let dayFirst = parts.contains { $0.first > 12 }
        let monthFirst = parts.contains { $0.second > 12 }
        switch (dayFirst, monthFirst) {
        case (true, false): return .dayFirst
        case (false, true): return .monthFirst
        default: return .unknown
        }
    }

    private static func instant(of parts: Parts, order: DateOrder, in zone: TimeZone) -> UTCInstant? {
        let (day, month): (Int, Int)
        switch order {
        case .dayFirst: (day, month) = (parts.first, parts.second)
        case .monthFirst: (day, month) = (parts.second, parts.first)
        case .unknown:
            guard parts.first == parts.second else { return nil }
            (day, month) = (parts.first, parts.second)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let wanted = DateComponents(
            year: parts.year, month: month, day: day, hour: parts.hour, minute: parts.minute)
        guard let date = calendar.date(from: wanted),
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date) == wanted
        else { return nil }
        return UTCInstant(date)
    }
}
