import Foundation
import Observation
import WorkbenchCore

@Observable
final class ReviewModel {
    static let days = 7

    private(set) var items: [Item] = []
    private(set) var selected = 0
    let problems = ProblemSlot()
    var problem: String? { problems.text }
    @ObservationIgnored private var undoStack: [(id: Int64, state: Mark, task: String)] = []

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let crew: Crew

    init(store: Store, crew: Crew) {
        self.store = store
        self.crew = crew
        refresh()
        crew.onItemsChanged { [weak self] in self?.refresh() }
    }

    var questions: Int { items.filter { $0.askedWith != nil }.count }
    var canUndo: Bool { !undoStack.isEmpty }
    var current: Item? { items.indices.contains(selected) ? items[selected] : nil }

    func helper(for item: Item) -> HelperModel? {
        crew.machines.first { $0.spec.task == Trial.machineTask(of: item.task) }
    }

    func name(of item: Item) -> String { crew.name(ofTask: item.task) }

    func refresh() {
        problems.attempt("read the queue", clearing: true) {
            items = try store.queries.waitingItems(since: WorkDay(containing: store.clock()).adding(days: -Self.days))
            selected = min(selected, max(items.count - 1, 0))
        }
    }

    func select(_ index: Int) { selected = max(0, min(index, items.count - 1)) }
    func next() { select(selected + 1) }
    func previous() { select(selected - 1) }

    func mark(_ mark: Mark) {
        guard let item = current, let id = item.id else { return }
        save(mark, on: item)
        undoStack.append((id, item.state, item.task))
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        problems.attempt("undo") { try store.mark(item: last.id, as: last.state) }
        changed(crew.machines.first { $0.spec.task == Trial.machineTask(of: last.task) })
        if let index = items.firstIndex(where: { $0.id == last.id }) { selected = index }
    }

    private func save(_ mark: Mark, on item: Item) {
        guard let id = item.id else { return }
        problems.attempt("save the mark") { try store.mark(item: id, as: mark) }
        changed(helper(for: item))
    }

    private func changed(_ helper: HelperModel?) {
        refresh()
        guard let helper else { return }
        helper.reload()
        helper.itemsChanged()
    }
}
