import Foundation
import LocalSources
import Observation

/// The one problem a page shows. Work that fails reports here. A task the app cancelled is not a problem.
@Observable
final class ProblemSlot {
    private(set) var text: String?
    private(set) var settingsPane: String?

    /// Runs `work` and shows "Could not <step>" when it fails. With `clearing`, success takes the old problem away.
    func attempt(_ step: String, clearing: Bool = false, _ work: () throws -> Void) {
        do {
            try work()
            if clearing { dismiss() }
        } catch {
            report(step, error)
        }
    }

    func report(_ step: String, _ error: any Error) {
        guard !Self.isCancellation(error) else { return }
        text = "Could not \(step): \(error.localizedDescription)"
        settingsPane = (error as? ReadError) == .notPermitted ? "Privacy_AllFiles" : nil
    }

    func show(_ message: String) {
        text = message
        settingsPane = nil
    }

    func dismiss() {
        text = nil
        settingsPane = nil
    }

    /// A cancelled task may fail with its own error on the way out; the cancel is what happened.
    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || Task.isCancelled
    }
}
