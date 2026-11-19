import Foundation
import Observation
import WorkbenchCore

/// Everything the crew proposed that still waits for the founder's mark, from every machine, in one list. The app's
/// random picks come first, because their answers are the fair measure of each machine.
@Observable
final class ReviewModel {
    /// How far back the queue reaches.
    static let days = 7

    private(set) var items: [Item] = []
    private(set) var selected = 0
    private(set) var problem: String?
    @ObservationIgnored private var undoStack: [(id: Int64, state: Mark)] = []

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let crew: Crew

    init(store: Store, crew: Crew) {
        self.store = store
        self.crew = crew
        refresh()
        crew.itemsChanged = { [weak self] in self?.refresh() }
    }

    var questions: Int { items.filter { $0.askedWith != nil }.count }
    var canUndo: Bool { !undoStack.isEmpty }
    var current: Item? { items.indices.contains(selected) ? items[selected] : nil }

    func helper(for item: Item) -> HelperModel? { crew.machines.first { $0.spec.task == item.task } }

    func refresh() {
        do {
            items = try store.queries.waitingItems(since: WorkDay(containing: store.clock()).adding(days: -Self.days))
            selected = min(selected, max(items.count - 1, 0))
            problem = nil
        } catch {
            problem = "Could not read the queue: \(error.localizedDescription)"
        }
    }

    func select(_ index: Int) { selected = max(0, min(index, items.count - 1)) }
    func next() { select(selected + 1) }
    func previous() { select(selected - 1) }

    /// Marks the selected item and moves to the next one waiting.
    func mark(_ mark: Mark) {
        guard let item = current, let id = item.id else { return }
        save(mark, on: item)
        undoStack.append((id, item.state))
    }

    /// Takes the last mark back, so the item waits again.
    func undo() {
        guard let last = undoStack.popLast() else { return }
        do {
            try store.mark(item: last.id, as: last.state)
        } catch {
            problem = "Could not undo: \(error.localizedDescription)"
        }
        refresh()
        if let index = items.firstIndex(where: { $0.id == last.id }) { selected = index }
        for machine in crew.machines { machine.reload() }
    }

    private func save(_ mark: Mark, on item: Item) {
        guard let id = item.id else { return }
        do {
            try store.mark(item: id, as: mark)
        } catch {
            problem = "Could not save the mark: \(error.localizedDescription)"
        }
        refresh()
        helper(for: item)?.reload()
    }
}
