import AppKit
import Foundation

/// Changing the profile: save the choice outside both stores, then start the app again, which reads it. Neither store
/// is opened or changed by the switch.
enum ProfileSwitch {
    static func title(to target: Profile) -> String {
        target.isDemo ? "Open the demo" : "Back to your data"
    }

    static func sentence(to target: Profile) -> String {
        target.isDemo
            ? "Workbench restarts with synthetic data. Your data stays as it is."
            : "Workbench restarts with your data. The demo stays as it is."
    }

    static let demoLabel = "Demo · synthetic data"

    /// Said while a machine reads, because the restart stops the reading.
    static func readingWarning(machines: [String]) -> String? {
        guard !machines.isEmpty else { return nil }
        let list = machines.formatted(.list(type: .and))
        return "\(list) \(machines.count == 1 ? "is" : "are") reading now. The restart stops the reading."
    }

    /// Whether the demo has been built on this Mac, so that the switch to it can open it.
    static var demoIsBuilt: Bool { Profile.demo.refusal(for: Profile.demo.defaultFolder) == nil }

    /// The data the app can switch to from `profile` now: back to yours from the demo, or to the demo once it is built.
    static func available(from profile: Profile) -> Profile? {
        profile.isDemo ? .yours : demoIsBuilt ? .demo : nil
    }

    /// Saves the choice and restarts. When the restart fails, the earlier choice comes back and the answer says why
    /// in one sentence; when it works, this process ends and the answer is never read.
    @MainActor
    static func change(
        to target: Profile, defaults: UserDefaults = .standard, restart: () async throws -> Void = restartApp
    ) async -> String? {
        let before = Profile.saved(in: defaults)
        target.save(in: defaults)
        do {
            try await restart()
            return nil
        } catch {
            before.save(in: defaults)
            return "Workbench could not restart. Your data stays as it is."
        }
    }

    /// The click: switches, and tells the person in an alert when the restart did not work.
    @MainActor
    static func go(to target: Profile) {
        Task {
            guard let problem = await change(to: target) else { return }
            let alert = NSAlert()
            alert.messageText = problem
            alert.runModal()
        }
    }

    @MainActor
    static func restartApp() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        NSApp.terminate(nil)
    }
}
