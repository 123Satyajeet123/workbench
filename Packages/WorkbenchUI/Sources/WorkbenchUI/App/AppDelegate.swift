import AgentCLI
import AppKit
import Foundation
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
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
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if case .ready(let session) = launch { island = IslandPanel(session: session) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        RunningChildren.terminateAll(grace: .seconds(2))
    }
}

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
