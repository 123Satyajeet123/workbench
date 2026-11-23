import Foundation
import WorkbenchCore

/// Acts on facts through Today's model: a close, a snooze, a hide or a wrong, each of which Undo takes back.
final class TodayActing: FactActing {
    private let model: TodayModel
    private let crew: Crew
    private let now: () -> Date

    init(model: TodayModel, crew: Crew, now: @escaping () -> Date = { .now }) {
        self.model = model
        self.crew = crew
        self.now = now
    }

    func offered(for item: Item) -> [FactAction] {
        let isOpen = item.isOpen(in: crew.lifecycle(ofTask: item.task), at: now())
        return FactAction.offered(for: item, isOpenFact: isOpen).filter { choice(for: $0) != nil }
    }

    func perform(_ action: FactAction, on items: [Item], surface: Surface) throws -> (() -> Void)? {
        guard let choice = choice(for: action) else { return nil }
        let problem = model.problem
        model.dismissUndo()
        model.perform(choice, on: items, text: action.title)
        guard model.undoable != nil else {
            if model.problem != problem, let reason = model.problem { throw FactActionError(reason: reason) }
            return nil
        }
        return { [model] in model.undo() }
    }

    private func choice(for action: FactAction) -> FactChoice? {
        switch action {
        case .done: .done
        case .snooze(let days): .snooze(until: model.today.adding(days: days))
        case .notRelevant: .notRelevant
        case .wrong: .wrong
        case .right: nil
        }
    }
}
