import SwiftUI
import WorkbenchCore

/// The facts the window can put in its panel by id or find by words: Today's needs, then what waits in Checks. A fact in
/// both lists comes once.
enum ShellFacts {
    static func open(today: TodayModel, review: ReviewModel) -> [TitledItem] {
        var seen: Set<Int64> = []
        let all: [TitledItem] =
            today.needs.map { ($0.item, today.title(of: $0.item)) }
            + review.items.map { item in
                (item, review.helper(for: item).map { item[$0.spec.title] } ?? item.quote)
            }
        return all.filter { entry in entry.item.id.map { seen.insert($0).inserted } ?? false }
    }

    static func item(_ id: Int64, in facts: [TitledItem]) -> Item? {
        facts.first { $0.item.id == id }?.item
    }
}

/// How the window acts on the fact in its panel: the model of the page that is open, so a fact is marked the same way
/// there and here.
@MainActor
final class ShellActing {
    private let today: TodayActing
    private let review: ReviewActing
    private let crew: Crew

    init(today: TodayModel, review: ReviewModel, crew: Crew) {
        self.today = TodayActing(model: today, crew: crew)
        self.review = ReviewActing(model: review)
        self.crew = crew
    }

    func acting(for page: SidebarSelection) -> any FactActing {
        switch page {
        case .review: review
        case .machine(let id): crew.helper(id: id).map { MachineActing(helper: $0) } ?? today
        default: today
        }
    }
}

extension Surface {
    init(page: SidebarSelection) {
        switch page {
        case .review: self = .review
        case .machine: self = .machinePage
        default: self = .today
        }
    }
}

extension EnvironmentValues {
    /// How the open page acts on a fact. The window sets it; a list and the right panel read it.
    @Entry var factActing: (any FactActing)?
    @Entry var factSurface = Surface.today
}
