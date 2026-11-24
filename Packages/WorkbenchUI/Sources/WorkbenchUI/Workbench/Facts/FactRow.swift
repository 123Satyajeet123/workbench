import Foundation
import WorkbenchCore

/// One fact as a list draws it: the item, its headline, and the chat it was said in. The id is the item's, so a row
/// keeps its place when the list reloads.
struct FactRow: Identifiable, Equatable {
    let id: Int64
    let item: Item
    let headline: FactHeadline
    let chat: String?

    /// Nil for an item with no id: nothing can mark it. `title` is the machine's own line, shown only when the item has
    /// no quote.
    init?(item: Item, title: String, chat: String? = nil, grouping: String? = nil) {
        guard let id = item.id else { return nil }
        self.id = id
        self.item = item
        self.chat = chat
        headline = FactHeadline(item: item, title: title, grouping: grouping)
    }
}

extension FactRow {
    /// Where and when it was said: the chat, else the project, else the source; then how long ago.
    func said(now: Date) -> String {
        [place, Self.ago(item.start, now: now)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var place: String {
        let source = item.source.words
        if let chat, !chat.isEmpty {
            return chat.caseInsensitiveCompare(headline.person) == .orderedSame ? source : chat
        }
        let project = item["project"]
        return project.isEmpty ? source : project
    }

    /// The due day and how urgent it is; nil when the fact has no due day.
    func due(today: WorkDay) -> (text: String, tone: Tone)? {
        guard let day = item.dueDay else { return nil }
        let tone: Tone = day < today ? .bad : (day == today ? .attention : .neutral)
        guard day != today else { return ("due today", tone) }
        let near = today.adding(days: -6)...today.adding(days: 6)
        let text =
            near.contains(day)
            ? day.start.formatted(.dateTime.weekday(.abbreviated)) : day.start.formatted(.dateTime.day().month())
        return ("due \(text)", tone)
    }

    /// What VoiceOver reads: the headline, where and when, and the due day.
    func spoken(now: Date) -> String {
        [headline.plain, said(now: now), due(today: WorkDay(containing: now))?.text ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ". ")
    }

    private static func ago(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
