import AgentCLI
import AppKit
import Foundation
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opened when the app first asks for it, so making a delegate opens no store.
    lazy var launch = AppLaunch.start(profile: profile, storeFolder: storeFolder)
    private let storeFolder: URL
    private let profile: Profile
    private var island: IslandPanel?
    /// What the founder did on a notification, held until the session can act on it.
    let replies = NotificationReplies()
    private var popup: PopupPanel?

    init(storeFolder: URL, profile: Profile = .yours) {
        self.storeFolder = storeFolder
        self.profile = profile
        super.init()
    }

    /// The saved profile chooses the folder, once, here.
    override convenience init() {
        let profile = Profile.saved()
        self.init(storeFolder: profile.defaultFolder, profile: profile)
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
            session.browsers.refreshEnabledBrowsers()
            popup = PopupPanel(session: session)
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
        if case .ready(let session) = launch { session.capture.endForQuit() }
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
