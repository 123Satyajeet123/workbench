import AgentCLI
import AppKit
import Foundation
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opened when the app first asks for it, so making a delegate opens no store.
    lazy var launch = AppLaunch.start(storeFolder: storeFolder)
    private let storeFolder: URL
    private var island: IslandPanel?

    init(storeFolder: URL) {
        self.storeFolder = storeFolder
        super.init()
    }

    override convenience init() {
        self.init(storeFolder: AppLaunch.defaultStoreFolder)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        AppTheme.saved().apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if case .ready(let session) = launch { island = IslandPanel(session: session) }
        DispatchQueue.main.async(execute: Self.comeToFront)
    }

    private static func comeToFront() {
        NSApp.activate()
        for window in NSApp.windows where window.isVisible && window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        RunningChildren.terminateAll(grace: .seconds(2))
    }
}

/// A click on a Workbench notification opens the page it is about; one shown while Workbench is in front still
/// appears.
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let page = SystemNotifier.page(of: response) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(page) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
