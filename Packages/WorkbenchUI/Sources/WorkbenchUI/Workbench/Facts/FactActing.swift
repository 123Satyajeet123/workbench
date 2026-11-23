import Foundation
import WorkbenchCore

/// The store did not take an action.
struct FactActionError: LocalizedError {
    let reason: String?

    var errorDescription: String? { reason ?? "Could not save that." }
}

/// How a surface acts on facts. It answers with the actions it offers, and it does an action through the model of
/// the page it serves, so one fact is marked in one way on every page.
protocol FactActing: AnyObject {
    func offered(for item: Item) -> [FactAction]

    /// Does `action` on `items`. Returns what takes it back, or nil when nothing changed: another page may have handled
    /// the fact already.
    func perform(_ action: FactAction, on items: [Item], surface: Surface) throws -> (() -> Void)?
}

extension Crew {
    /// The lifecycle of the facts of `task`: a machine's own, a deal's action or a revisit. Nil for a task whose items
    /// never open and close.
    func lifecycle(ofTask task: String) -> HelperSpec.Lifecycle? {
        switch task {
        case DealAction.task: DealAction.lifecycle
        case Revisit.task: Revisit.lifecycle
        default: machines.first { $0.spec.task == task }?.spec.lifecycle
        }
    }
}
