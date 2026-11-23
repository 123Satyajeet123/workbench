import Foundation
import WorkbenchCore

/// Why a fact is on a list, in a word.
enum FactReason: Equatable {
    case asksYou, overdue, picked, actToday, worthALook, revisit, news

    var text: String {
        switch self {
        case .asksYou: "Asks you"
        case .overdue: "Overdue"
        case .picked: "Picked at random"
        case .actToday: "Act today"
        case .worthALook: "Worth a look"
        case .revisit: "Revisit"
        case .news: "News"
        }
    }

    var tone: Tone {
        switch self {
        case .asksYou, .actToday: .attention
        case .overdue: .bad
        case .picked, .worthALook, .revisit, .news: .neutral
        }
    }

    /// The word for a line of Today's "Needs you". A fact that is due today or later has its day on the card, so it
    /// needs no word.
    init?(_ reason: Need.Reason, today: WorkDay) {
        switch reason {
        case .act: self = .actToday
        case .watch: self = .worthALook
        case .asks: self = .asksYou
        case .due(let day):
            guard day < today else { return nil }
            self = .overdue
        case .revisit: self = .revisit
        case .news: self = .news
        }
    }
}

/// One fact as a list draws it: the item, the line it shows, and why it is there. The id is the item's, so a row
/// keeps its place when the list reloads.
struct FactRow: Identifiable, Equatable {
    let id: Int64
    let item: Item
    let title: String
    let reason: FactReason?

    /// Nil for an item with no id: nothing can mark it. An item the app picked at random says so, whatever else it is.
    init?(item: Item, title: String, reason: FactReason? = nil) {
        guard let id = item.id else { return nil }
        self.id = id
        self.item = item
        self.title = title
        self.reason = item.askedWith != nil ? .picked : reason
    }

    var person: String { item["person"] }
}

extension FactRow {
    /// Person, project, source and how long ago, each when the item has it.
    func meta(now: Date) -> String {
        [person, item["project"], Self.sourceName(item.source), Self.ago(item.start, now: now)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The due day and how urgent it is; nil when the fact has no due day.
    func due(today: WorkDay) -> (text: String, tone: Tone)? {
        guard let day = item.dueDay else { return nil }
        let tone: Tone = day < today ? .bad : (day == today ? .attention : .neutral)
        let near = today.adding(days: -6)...today.adding(days: 6)
        let text =
            near.contains(day)
            ? day.start.formatted(.dateTime.weekday(.abbreviated)) : day.start.formatted(.dateTime.day().month())
        return (text, tone)
    }

    /// What VoiceOver reads: the title, the person, the due day and the reason.
    func spoken(today: WorkDay) -> String {
        [title, person, due(today: today).map { "Due \($0.text)" } ?? "", reason?.text ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ". ")
    }

    private static func sourceName(_ source: SourceKind) -> String {
        switch source {
        case .whatsapp: "WhatsApp"
        case .mail: "Mail"
        case .screen, .screenText: "Screen"
        case .call: "Call"
        case .calendar: "Calendar"
        case .web: "Web"
        case .files: "Files"
        case .typed: "You"
        }
    }

    private static func ago(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

extension [FactRow] {
    /// The rows a list draws while some rows confirm an action. A confirming row that the new rows no longer hold stays
    /// where it was, until its confirmation ends.
    func displayed(replacing incoming: [FactRow], keeping confirming: Set<Int64>) -> [FactRow] {
        var result = incoming
        let present = Set(incoming.map(\.id))
        for (index, row) in enumerated() where confirming.contains(row.id) && !present.contains(row.id) {
            let before = self[..<index].reversed().compactMap { earlier in result.firstIndex { $0.id == earlier.id } }
            result.insert(row, at: before.first.map { $0 + 1 } ?? 0)
        }
        return result
    }
}

extension [FactRow] {
    /// The rows a list shows when it keeps `limit` rows, and how many it holds back.
    func capped(at limit: Int, showingAll: Bool) -> (shown: [FactRow], hidden: Int) {
        let shown = showingAll ? self : Array(prefix(limit))
        return (shown, count - shown.count)
    }
}
