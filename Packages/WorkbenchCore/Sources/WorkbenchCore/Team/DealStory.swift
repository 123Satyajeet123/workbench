import Foundation

/// What happened to one deal, in time order, from rows the store already holds: where it was captured, how the
/// criteria rated it, what the person marked, how it moved, and the actions opened and closed. It calls no model.
public struct DealStory: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable {
            case captured, rated, marked, stage, note, owner, actionOpened, actionClosed
        }

        public var id: String
        public var at: Date
        public var kind: Kind
        /// The person, or the machine for a rating.
        public var actor: String
        public var isMachine: Bool
        public var text: String
    }

    public struct Ribbon: Equatable, Sendable {
        /// Where its items were captured from, once each, in the order they came.
        public var sources: [String]
        public var rating: String?
        /// The person's latest mark on the item that was rated; nil when none was made.
        public var mark: Mark?
        public var moves: Int
        public var actionsOpened: Int
        public var actionsClosed: Int

        public init(
            sources: [String], rating: String?, mark: Mark?, moves: Int, actionsOpened: Int, actionsClosed: Int
        ) {
            self.sources = sources
            self.rating = rating
            self.mark = mark
            self.moves = moves
            self.actionsOpened = actionsOpened
            self.actionsClosed = actionsClosed
        }
    }

    public struct Marked: Equatable, Sendable {
        public var state: Mark
        public var at: Date

        public init(state: Mark, at: Date) {
            self.state = state
            self.at = at
        }
    }

    public var entries: [Entry]
    public var ribbon: Ribbon

    /// The story of `deal`. `ratings` and `marks` are keyed by the id of the event that linked the item; `actions`
    /// are the deal's action facts.
    public static func make(
        deal: WorkObject, ratings: [String: String], marks: [String: [Marked]], actions: [Item]
    ) -> DealStory {
        var entries: [Entry] = []
        let readable = Set(deal.items.map(\.event.id))
        for event in deal.history {
            switch event.kind {
            case .link:
                guard readable.contains(event.id), let item = event.item else { continue }
                entries += captured(event, item, rating: ratings[event.id], marks: marks[event.id] ?? [])
            case .stage:
                let moved = !event.replaces.isEmpty
                let label = deal.type.resolveStage(event.text).label
                entries.append(
                    person(event, .stage, moved ? "Moved to \(label)" : "Started in \(label)"))
            case .note: entries.append(person(event, .note, "Wrote a note"))
            case .claim: entries.append(person(event, .owner, "Took it"))
            case .release: entries.append(person(event, .owner, "Let it go"))
            case .create, .title, .archive: break
            }
        }
        for action in actions { entries += self.entries(of: action) }
        entries.sort { ($0.at, $0.id) < ($1.at, $1.id) }
        return DealStory(
            entries: entries,
            ribbon: Ribbon(
                sources: sources(of: deal), rating: deal.items.compactMap { ratings[$0.event.id] }.first,
                mark: deal.items.compactMap { marks[$0.event.id]?.last?.state }.first(where: { $0 != .proposed }),
                moves: deal.history.filter { $0.kind == .stage && !$0.replaces.isEmpty }.count,
                actionsOpened: actions.count, actionsClosed: actions.filter { $0.closed != nil }.count))
    }

    private static func person(_ event: WorkEvent, _ kind: Entry.Kind, _ text: String) -> Entry {
        Entry(id: event.id, at: event.at, kind: kind, actor: event.author, isMachine: false, text: text)
    }

    private static func captured(_ event: WorkEvent, _ item: LinkedItem, rating: String?, marks: [Marked])
        -> [Entry]
    {
        var entries = [
            Entry(
                id: event.id, at: event.at, kind: .captured, actor: event.author, isMachine: false,
                text: "Captured from \(item.source?.capturedFrom ?? "an unknown source"): “\(item.quote)”")
        ]
        if let rating {
            entries.append(
                Entry(
                    id: event.id + ".rated", at: event.at, kind: .rated, actor: item.machine, isMachine: true,
                    text: "Rated \(rating) by the criteria"))
        }
        entries += marks.enumerated().filter { $0.element.state != .proposed }.map { index, marked in
            Entry(
                id: "\(event.id).mark\(index)", at: marked.at, kind: .marked, actor: event.author, isMachine: false,
                text: marked.state == .confirmed ? "Marked the reading right" : "Marked the reading wrong")
        }
        return entries
    }

    private static func entries(of action: Item) -> [Entry] {
        let id = "action\(action.id ?? 0)"
        let due = action.dueDay.map { ", due \($0)" } ?? ""
        var entries = [
            Entry(
                id: id, at: action.start, kind: .actionOpened, actor: action["person"], isMachine: false,
                text: "Waiting on: \(action["text"])\(due)")
        ]
        if let closed = action.closed {
            entries.append(
                Entry(
                    id: id + ".closed", at: closed.at, kind: .actionClosed, actor: action["person"], isMachine: false,
                    text: "Action \(closed.outcome)"))
        }
        return entries
    }

    private static func sources(of deal: WorkObject) -> [String] {
        var seen: [String] = []
        for linked in deal.items {
            let source = linked.item.source?.capturedFrom ?? "an unknown source"
            if !seen.contains(source) { seen.append(source) }
        }
        return seen
    }
}

extension SourceKind {
    public var capturedFrom: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .telegram: "Telegram"
        case .screenText: "a page"
        case .screen: "the screen"
        case .typed: "you"
        default: "another source"
        }
    }
}

extension Queries {
    /// The marks on an item, oldest first.
    public func marks(ofItem id: Int64) throws -> [DealStory.Marked] {
        try reader.read { db in
            try db.fetch("mark", "SELECT state, ts FROM mark WHERE item_id = ? ORDER BY id", [id]) { row in
                DealStory.Marked(state: try row.enumeration("state"), at: try row.date("ts"))
            }
        }
    }
}
