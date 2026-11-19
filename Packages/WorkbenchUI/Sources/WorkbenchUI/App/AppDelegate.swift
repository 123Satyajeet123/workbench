import AgentCLI
import AppKit
import Foundation

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        if case .ready(let session) = launch { island = IslandPanel(capture: session.capture) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        RunningChildren.terminateAll(grace: .seconds(2))
    }
}
