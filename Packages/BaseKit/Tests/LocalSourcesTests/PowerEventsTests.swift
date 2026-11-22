import AppKit
import Testing

@testable import LocalSources

@MainActor @Suite struct PowerEventsTests {
    @MainActor final class Heard { var count = 0 }

    @Test func aWatcherThatIsLetGoHearsNoMoreWakes() async throws {
        let heard = Heard()
        var watcher: PowerEvents? = PowerEvents { _ in heard.count += 1 }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(heard.count == 1)
        watcher = nil
        _ = watcher
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(heard.count == 1)
    }
}
