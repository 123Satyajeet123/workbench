import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

/// A real window around the shell, as the app opens it, for tests that draw it or change its size.
@MainActor
final class ShellWindow {
    let window: NSWindow

    init(session: AppSession, size: CGSize, zoom: Double = 1, dark: Bool = false) {
        let root = WorkbenchView(session: session).zoomed(Zoom(zoom)).background(.pageFill).environment(session)
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = []
        window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.collectionBehavior = [.fullScreenPrimary]
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: 40, y: 80))
        window.isReleasedWhenClosed = false
    }

    deinit { MainActor.assumeIsolated { window.close() } }

    func show(settle seconds: Double = 1.2) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        settle(seconds)
    }

    func settle(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// The window as the screen shows it, with its title bar and the system's own sidebar, as a PNG.
    func png(to file: URL) throws {
        let capture = Process()
        capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
        try capture.run()
        capture.waitUntilExit()
    }

    func save(_ name: String) throws {
        let folder =
            ProcessInfo.processInfo.environment["SHELL_SHOTS_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png(to: folder.appending(path: "\(name).png"))
    }
}
