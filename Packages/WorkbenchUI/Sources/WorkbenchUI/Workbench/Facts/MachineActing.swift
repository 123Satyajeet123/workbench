import Foundation
import WorkbenchCore

/// Acts on the facts of one machine's own page: a mark right or wrong, and a close with the lifecycle's outcome.
final class MachineActing: FactActing {
    private let helper: HelperModel
    private let now: () -> Date

    init(helper: HelperModel, now: @escaping () -> Date = { .now }) {
        self.helper = helper
        self.now = now
    }

    func offered(for item: Item) -> [FactAction] {
        let current = current(item)
        let isOpen = current.isOpen(in: helper.spec.lifecycle, at: now())
        return FactAction.offered(for: current, isOpenFact: isOpen).filter(isSupported)
    }

    func perform(_ action: FactAction, on items: [Item], surface: Surface) throws -> (() -> Void)? {
        let doable = items.map(current).filter { offered(for: $0).contains { $0.sameKind(as: action) } }
        guard !doable.isEmpty else { return nil }
        let problem = helper.problem
        let undos = doable.compactMap { change($0, by: action) }
        if helper.problem != problem, let reason = helper.problem { throw FactActionError(reason: reason) }
        return {
            for undo in undos { undo() }
        }
    }

    private func isSupported(_ action: FactAction) -> Bool {
        switch action {
        case .right, .wrong, .done: true
        case .snooze, .notRelevant: false
        }
    }

    /// The item as the machine holds it now, which may differ from the copy a row shows.
    private func current(_ item: Item) -> Item {
        (helper.items + helper.open).first { $0.id == item.id } ?? item
    }

    private func change(_ item: Item, by action: FactAction) -> (() -> Void)? {
        switch action {
        case .right: return marking(item, as: .confirmed)
        case .wrong: return marking(item, as: .rejected)
        case .done:
            guard let lifecycle = helper.spec.lifecycle else { return nil }
            helper.close(item, as: lifecycle.doneOutcome(of: item))
            return { [helper] in helper.reopen(item) }
        case .snooze, .notRelevant: return nil
        }
    }

    /// Marking the same way again takes a mark back, so Undo is the same call on the marked item.
    private func marking(_ item: Item, as mark: Mark) -> () -> Void {
        helper.mark(item, as: mark)
        var marked = item
        marked.state = mark
        return { [helper] in helper.mark(marked, as: mark) }
    }
}
