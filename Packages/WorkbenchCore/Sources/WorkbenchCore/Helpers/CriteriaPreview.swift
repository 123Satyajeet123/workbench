import Foundation

public struct CriteriaPreview: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: Int64?
        public var title: String
        public var was: Rating
        public var now: Rating
        public var needsReview: Bool
        public var unread: Int

        public var isChanged: Bool { was != now }
    }

    public var rows: [Row]

    public var changed: [Row] { rows.filter(\.isChanged) }
    public var unread: Int { rows.filter { $0.unread > 0 }.count }

    public init(items: [Item], title: String, current: Criteria, edited: Criteria) {
        rows = items.map { item in
            let after = edited.triage(item.fields)
            return Row(
                id: item.id, title: item[title], was: current.triage(item.fields).rating, now: after.rating,
                needsReview: after.needsReview, unread: after.results.filter { !$0.isRead }.count)
        }
    }
}
