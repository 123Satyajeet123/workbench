import AgentCLI
import AppKit
import Foundation
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opened when the app first asks for it, so making a delegate opens no store.
    lazy var launch = AppLaunch.start(storeFolder: storeFolder)
    private let storeFolder: URL
    private var island: IslandPanel?
    /// What the founder did on a notification, held until the session can act on it.
    let replies = NotificationReplies()

    init(storeFolder: URL) {
        self.storeFolder = storeFolder
        super.init()
    }

    override convenience init() {
        self.init(storeFolder: AppLaunch.defaultStoreFolder)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        SystemNotifier.registerCategories()
        AppTheme.saved().apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if case .ready(let session) = launch {
            island = IslandPanel(session: session)
            let answering = NotificationAnswering(
                today: session.today, review: session.review, crew: session.crew, navigation: session.navigation)
            replies.handler = answering.handle
        }
        DispatchQueue.main.async(execute: Self.comeToFront)
    }

    private static func comeToFront() {
        NSApp.activate(ignoringOtherApps: true)
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

/// A mark chosen on a Workbench notification goes to `replies` and opens nothing. A click on the body opens the page
/// it is about, and tells `replies` which fact.
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let reply = SystemNotifier.reply(to: response)
        let page = response.actionIdentifier == NotificationReply.bodyClick ? SystemNotifier.page(of: response) : nil
        await MainActor.run {
            if let reply { replies.receive(reply) }
            if let page { _ = NSWorkspace.shared.open(page) }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
