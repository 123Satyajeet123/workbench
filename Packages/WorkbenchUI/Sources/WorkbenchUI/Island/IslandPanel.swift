import AppKit
import SwiftUI

/// Shows the island above every window. It never takes the keyboard, and takes a click only when it offers the
/// review queue; a click opens Workbench on Review.
final class IslandPanel: NSPanel {
    init(session: AppSession) {
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
        let content = NSHostingView(
            rootView: IslandContent(session: session) { [weak self] in self?.ignoresMouseEvents = !$0 })
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

    override var canBecomeKey: Bool { false }
}

extension Notification.Name {
    /// Asks the main window to show the review queue.
    static let openReview = Notification.Name("WorkbenchOpenReview")
}

private struct IslandContent: View {
    let session: AppSession
    let takesClicks: (Bool) -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        IslandView(state: state)
            .contentShape(Rectangle())
            .onTapGesture {
                guard state.takesClicks else { return }
                openWindow(id: WorkbenchApp.mainWindowID)
                NSApp.activate()
                NotificationCenter.default.post(name: .openReview, object: nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: state.takesClicks, initial: true) { _, takes in takesClicks(takes) }
    }

    private var state: IslandState {
        IslandState(
            recordingSince: session.capture.call?.startedAt,
            reading: session.crew.machines.filter { $0.phase == .reading }.map(\.name),
            waiting: session.review.items.count)
    }
}
