import Foundation
import WorkbenchCore

/// A value a person typed into the chip of a setting, read as the kind of value that chip holds. This is format
/// parsing against a closed vocabulary, like a date field: it reads numbers, times and on or off words, never meaning.
/// What does not parse, or lies outside the limits, is refused with the reason in words for the person.
enum SettingEdit {
    struct Refusal: Error, Equatable {
        let reason: String
    }

    static let minutes = 5...720
    static let hours = 0...23

    static func onOff(_ text: String) throws -> Bool {
        switch text.trimmed.lowercased() {
        case "on", "yes", "true": return true
        case "off", "no", "false": return false
        default: throw Refusal(reason: "Write on or off.")
        }
    }

    static func number(_ text: String, in range: ClosedRange<Int>, of what: String) throws -> Int {
        guard let value = Int(text.trimmed), text.trimmed.allSatisfy(\.isNumber), range.contains(value) else {
            throw Refusal(reason: "\(what) is a whole number from \(range.lowerBound) to \(range.upperBound).")
        }
        return value
    }

    /// A time of day: `20:00`, `8`, `8 pm`, `8:30pm`. The hour is 0 to 23 on the 24-hour clock and 1 to 12 with am or pm.
    static func time(_ text: String) throws -> (hour: Int, minute: Int) {
        let forms = Refusal(reason: "Write a time such as 20:00, 8 PM or 8:30 PM.")
        var rest = text.trimmed.lowercased()
        var meridiem: String?
        for suffix in ["am", "pm"] where rest.hasSuffix(suffix) {
            meridiem = suffix
            rest = String(rest.dropLast(2)).trimmed
        }
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
            var hour = Int(parts[0]), let minute = parts.count == 2 ? Int(parts[1]) : 0, minute < 60
        else { throw forms }
        if let meridiem {
            guard (1...12).contains(hour) else { throw forms }
            hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
        }
        guard hours.contains(hour) else { throw forms }
        return (hour, minute)
    }

    /// A time of day in the words of the page: `8 PM`, `9:30 PM`.
    static func words(hour: Int, minute: Int) -> String {
        let clock = hour % 12 == 0 ? 12 : hour % 12
        return "\(clock)\(minute == 0 ? "" : ":" + String(format: "%02d", minute)) \(hour < 12 ? "AM" : "PM")"
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
