import Foundation
import LocalSources
import Observation

@Observable
final class ProblemSlot {
    private(set) var text: String?
    private(set) var settingsPane: PrivacyPane?

    func attempt(_ step: String, clearing: Bool = false, _ work: () throws -> Void) {
        do {
            try work()
            if clearing { dismiss() }
        } catch {
            report(step, error)
        }
    }

    func attempt(_ step: String, clearing: Bool = false, _ work: () async throws -> Void) async {
        do {
            try await work()
            if clearing { dismiss() }
        } catch {
            report(step, error)
        }
    }

    func report(_ step: String, _ error: any Error) {
        guard !Self.isCancellation(error) else { return }
        text = "Could not \(step): \(error.localizedDescription)"
        settingsPane = (error as? ReadError) == .notPermitted ? .fullDiskAccess : nil
    }

    func show(_ message: String) {
        text = message
        settingsPane = nil
    }

    func dismiss() {
        text = nil
        settingsPane = nil
    }

    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || Task.isCancelled
    }
}
