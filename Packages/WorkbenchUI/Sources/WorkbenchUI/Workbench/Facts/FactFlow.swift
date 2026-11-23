import Foundation
import Observation
import WorkbenchCore

/// Everything a list needs to act on one fact.
struct FactContext {
    let acting: any FactActing
    let surface: Surface
    let selection: FactSelection
    let toast: ToastCenter
    let undoManager: UndoManager?
    /// The items the list shows now, in order.
    let items: [Item]
}

/// Notification observers that end with their owner.
private nonisolated final class Observers: @unchecked Sendable {
    nonisolated(unsafe) var tokens: [NSObjectProtocol] = []

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}

/// What happens when a person acts on a fact in a list: the surface does it, the window's undo manager learns how to
/// take it back, a toast says what happened, and the row confirms before it leaves.
@Observable
final class FactFlow {
    private(set) var confirming: [Int64: FactAction] = [:]
    /// Rows whose height is closing. They leave the list when it has closed.
    private(set) var leaving: Set<Int64> = []

    @ObservationIgnored private let confirmation: Duration
    @ObservationIgnored private let closing: Duration
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var lastToast: Toast?
    @ObservationIgnored private let observers = Observers()
    @ObservationIgnored private weak var watchedManager: UndoManager?
    @ObservationIgnored private weak var watchedCenter: ToastCenter?

    init(
        confirmation: Duration = .milliseconds(300), closing: Duration = .seconds(Motion.duration),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.confirmation = confirmation
        self.closing = closing
        self.clock = clock
    }

    /// Rows the list keeps drawing until their leave ends.
    var held: Set<Int64> { Set(confirming.keys).union(leaving) }

    /// A row that another page handled: it closes its height, and then it goes.
    @discardableResult
    func retire(_ id: Int64) -> Task<Void, Never> {
        leaving.insert(id)
        return Task { [clock, closing] in
            try? await clock.sleep(for: closing)
            leaving.remove(id)
        }
    }

    func run(_ action: FactAction, on row: FactRow, in context: FactContext) async {
        guard confirming[row.id] == nil,
            context.acting.offered(for: row.item).contains(where: { $0.sameKind(as: action) })
        else { return }
        let undo: (() -> Void)?
        do {
            undo = try context.acting.perform(action, on: [row.item], surface: context.surface)
        } catch {
            context.toast.show(error.localizedDescription)
            return
        }
        guard let undo else { return }
        context.selection.leave(row.id, in: context.items)
        announce(action, on: row, undo: undo, in: context)
        confirming[row.id] = action
        try? await clock.sleep(for: confirmation)
        await retire(row.id).value
        confirming[row.id] = nil
    }

    private func announce(_ action: FactAction, on row: FactRow, undo: @escaping () -> Void, in context: FactContext) {
        let text = action.toastText(for: row.title)
        guard let manager = context.undoManager else { return context.toast.show(text) }
        manager.registerUndo(withTarget: manager) { _ in MainActor.assumeIsolated { undo() } }
        manager.setActionName(action.title)
        context.toast.show(text) { [weak manager] in manager?.undo() }
        lastToast = context.toast.current
        watch(manager, toast: context.toast)
    }

    /// Hides the toast when the undo stack changes by another route, for instance with ⌘Z.
    private func watch(_ manager: UndoManager, toast center: ToastCenter) {
        guard watchedManager !== manager || watchedCenter !== center else { return }
        observers.tokens.forEach(NotificationCenter.default.removeObserver)
        watchedManager = manager
        watchedCenter = center
        observers.tokens = [NSNotification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: manager, queue: nil) {
                [weak self, weak center] _ in
                MainActor.assumeIsolated {
                    guard let self, let center, center.current == self.lastToast else { return }
                    center.dismiss()
                }
            }
        }
    }
}
