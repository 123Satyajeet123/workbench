import AppKit
import SwiftUI

/// Shows the island above every window. It takes no click and never the keyboard.
final class IslandPanel: NSPanel {
    init(capture: CaptureSettings) {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true
        let content = NSHostingView(rootView: IslandContent(capture: capture))
        content.sizingOptions = []
        contentView = content
        if let screen = NSScreen.main {
            let size = IslandMetrics.panelSize
            setFrame(
                NSRect(
                    x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                    width: size.width, height: size.height), display: false)
        }
        orderFrontRegardless()
    }
}

private struct IslandContent: View {
    let capture: CaptureSettings

    var body: some View {
        IslandView(recordingSince: capture.call?.startedAt)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
