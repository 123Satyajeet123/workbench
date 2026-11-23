import Foundation
import Observation
import SwiftUI
import WorkbenchCore

/// Which fact a list has selected and which one the inspector shows. The inspector follows the selection.
@Observable
final class FactSelection {
    var selected: Int64?
    var inspected: Item?

    /// Moves the selection by `offset` rows, and stops at the first and last row. With nothing selected, a move down
    /// takes the first row and a move up takes the last.
    func move(by offset: Int, in items: [Item]) {
        let ids = items.compactMap(\.id)
        guard !ids.isEmpty else { return }
        if let selected, let index = ids.firstIndex(of: selected) {
            self.selected = ids[max(0, min(index + offset, ids.count - 1))]
        } else {
            selected = offset >= 0 ? ids.first : ids.last
        }
        if inspected != nil { inspected = items.first { $0.id == selected } }
    }

    func select(_ item: Item) {
        selected = item.id
    }

    func inspectSelected(in items: [Item]) {
        inspected = items.first { $0.id == selected }
    }

    /// Closes the inspector. Answers whether there was one to close.
    func closeInspector() -> Bool {
        defer { inspected = nil }
        return inspected != nil
    }

    /// A fact leaves the list. A selection or an inspector on it moves to the row after it, else the row before it.
    func leave(_ id: Int64, in items: [Item]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let others = items.filter { $0.id != id }
        let neighbour = others.indices.contains(index) ? others[index] : others.last
        if selected == id { selected = neighbour?.id }
        if inspected?.id == id { inspected = neighbour }
    }
}

/// What a key does in a list of facts.
enum FactCommand: Equatable {
    case move(Int)
    case act(FactAction)
    case inspect
    case closeInspector
}

enum FactKeys {
    private static let moves: [(KeyEquivalent, Int)] = [
        ("j", 1), (.downArrow, 1), ("k", -1), (.upArrow, -1),
    ]

    private static let actions: [FactAction] = [.right, .done, .snooze(days: 1), .notRelevant, .wrong]

    /// The command a key press runs, or nil when the key means nothing here. An action runs only when the selected fact
    /// is offered it.
    static func command(for key: KeyEquivalent, modifiers: EventModifiers, offered: [FactAction]) -> FactCommand? {
        guard modifiers.isEmpty else { return nil }
        if let move = moves.first(where: { $0.0 == key }) { return .move(move.1) }
        if key == .return || key == .space { return .inspect }
        if key == .escape { return .closeInspector }
        guard let action = actions.first(where: { KeyEquivalent(Character($0.key.lowercased())) == key }) else {
            return nil
        }
        return offered.first { $0.sameKind(as: action) }.map(FactCommand.act)
    }
}
