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
    init?(item: Item, title: String, chat: String? = nil) {
        guard let id = item.id else { return nil }
        self.id = id
        self.item = item
        self.chat = chat
        headline = FactHeadline(item: item, title: title)
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
