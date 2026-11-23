import Foundation
import WorkbenchCore

/// Acts on the review queue: right or wrong, in the queue's own mark path and with its own undo.
final class ReviewActing: FactActing {
    private let model: ReviewModel

    init(model: ReviewModel) {
        self.model = model
    }

    func offered(for item: Item) -> [FactAction] {
        FactAction.offered(for: item, isOpenFact: false)
    }

    func perform(_ action: FactAction, on items: [Item], surface: Surface) throws -> (() -> Void)? {
        guard let mark = mark(for: action) else { return nil }
        var marked = 0
        for item in items {
            guard let index = model.items.firstIndex(where: { $0.id == item.id }) else { continue }
            model.select(index)
            model.mark(mark)
            guard !model.items.contains(where: { $0.id == item.id }) else {
                throw FactActionError(reason: model.problem)
            }
            marked += 1
        }
        guard marked > 0 else { return nil }
        return { [model] in
            for _ in 0..<marked { model.undo() }
        }
    }

    private func mark(for action: FactAction) -> Mark? {
        switch action {
        case .right: .confirmed
        case .wrong: .rejected
        case .done, .snooze, .notRelevant: nil
        }
    }
}
