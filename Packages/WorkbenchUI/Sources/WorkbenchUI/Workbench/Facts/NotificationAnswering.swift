import Foundation
import WorkbenchCore

/// Does what the founder chose on a notification through the same actions as Today, with the notification as the
/// surface. A click on the body opens the fact. The notification goes from Notification Centre once its fact is
/// handled, or when its fact no longer waits; after a failed action it stays, so the founder can try again.
final class NotificationAnswering {
    private let today: TodayModel
    private let review: ReviewModel
    private let crew: Crew
    private let navigation: Navigation

    init(today: TodayModel, review: ReviewModel, crew: Crew, navigation: Navigation) {
        self.today = today
        self.review = review
        self.crew = crew
        self.navigation = navigation
    }

    func handle(_ reply: NotificationReply) {
        switch reply {
        case .open(let itemID): navigation.show(fact: itemID)
        case .answer(let answer): act(on: answer)
        }
    }

    private func act(on answer: NotificationAnswer) {
        guard let item = waiting.first(where: { $0.id == answer.itemID }) else {
            return crew.notifications.clear(itemID: answer.itemID)
        }
        guard (try? acting(for: answer.action).perform(answer.action.fact, on: [item], surface: .notification)) != nil
        else { return }
        crew.notifications.clear(itemID: answer.itemID)
    }

    private func acting(for action: NotificationAction) -> FactActing {
        action.isCheck ? ReviewActing(model: review) : TodayActing(model: today, crew: crew)
    }

    private var waiting: [Item] { today.needs.map(\.item) + review.items }
}

extension NotificationAction {
    var fact: FactAction {
        switch self {
        case .done: .done
        case .snooze1: .snooze(days: 1)
        case .right: .right
        case .wrong: .wrong
        }
    }

    var isCheck: Bool { self == .right || self == .wrong }
}
