import Foundation
import WorkbenchCore

/// Days and times in the words the inspector uses: "Thu 20 Nov", "Thu 20 Nov, 10:42", and just "Fri" for a day of the
/// last week.
struct DateWords {
    var now: Date
    var calendar = Calendar.current
    var locale = Locale.current

    private var dayStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).day()
            .month(.abbreviated)
    }

    private var weekdayStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
    }

    private var timeStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
    }

    func date(_ date: Date) -> String { date.formatted(dayStyle) }

    func time(_ date: Date) -> String { date.formatted(timeStyle) }

    func moment(_ date: Date) -> String { "\(self.date(date)), \(time(date))" }

    /// The weekday alone for a day in the last six days; the date for an older day.
    func recent(_ date: Date) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
        return (0..<7).contains(days.day ?? 7) ? date.formatted(weekdayStyle) : self.date(date)
    }
}

/// The plain-words lines of the inspector that are not proof lines.
enum InspectorWords {
    static func meta(of item: Item, _ words: DateWords) -> String {
        var parts = ["project", "company", "event", "feed"].map { item[$0] }.filter { !$0.isEmpty }
        if let due = item.dueDay { parts.append("due \(words.date(due.start))") }
        return parts.joined(separator: " · ")
    }

    /// Where the fact came from: the source, the chat if it has one, and the moment of the message.
    static func source(of item: Item, chat: String?, _ words: DateWords) -> String {
        [item.source.words, chat, words.moment(item.start)].compactMap { $0 }.joined(separator: " · ")
    }

    static let notFound = "The lines this came from are not here any more."
    static let deleted = "The message this came from was deleted."
    static func unreadable(_ reason: String) -> String { "Could not read the chat: \(reason)" }
}

extension SourceKind {
    /// The source as a person names it.
    var words: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .mail: "Mail"
        case .call: "Call"
        case .calendar: "Calendar"
        case .screen: "Screen"
        case .screenText: "Web page you read"
        case .web: "Web"
        case .files: "Files"
        case .typed: "Typed by you"
        }
    }
}
