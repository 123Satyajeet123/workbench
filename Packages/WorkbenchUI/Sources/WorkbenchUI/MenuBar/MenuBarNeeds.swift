import Foundation
import WorkbenchCore

struct MenuNeed: Equatable, Identifiable {
    let id: Int64
    let title: String
}

/// An item and the words the menu shows for it.
typealias TitledItem = (item: Item, title: String)

/// What waits for the person, as the menu bar counts and lists it: Today's needs, then the app's random picks that
/// no mark has answered, until the morning list holds both. An item in both lists counts once.
struct MenuBarNeeds: Equatable {
    static let listed = 3
    static let untitled = "Something to check"
    /// A menu grows as wide as its longest line, so a long title is cut.
    static let titleLimit = 48

    let count: Int
    let top: [MenuNeed]

    init(needs: [TitledItem], randomPicks: [TitledItem]) {
        var seen: Set<Int64> = []
        let all = (needs + randomPicks.filter { Self.isUnansweredPick($0.item) }).compactMap { entry -> MenuNeed? in
            guard let id = entry.item.id, seen.insert(id).inserted else { return nil }
            return MenuNeed(id: id, title: Self.shortened(entry.title))
        }
        count = all.count
        top = Array(all.prefix(Self.listed))
    }

    private static func shortened(_ title: String) -> String {
        if title.isEmpty { return untitled }
        return title.count > titleLimit ? title.prefix(titleLimit - 1) + "…" : title
    }

    /// An item the app picked to ask about, and the person has not marked.
    static func isUnansweredPick(_ item: Item) -> Bool { item.askedWith != nil && item.state == .proposed }
}

extension MenuBarNeeds {
    init(today: TodayModel, review: ReviewModel) {
        self.init(
            needs: today.needs.map { ($0.item, today.title(of: $0.item)) },
            randomPicks: review.items.map { item in
                (item, review.helper(for: item).map { item[$0.spec.title] } ?? item.quote)
            })
    }
}
