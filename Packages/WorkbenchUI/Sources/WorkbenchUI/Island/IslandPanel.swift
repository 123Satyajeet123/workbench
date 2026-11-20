import AppKit
import SwiftUI

/// Shows the island above every window, on the screen with the notch, and moves it when screens change. It never
/// takes the keyboard, and takes a click only when it offers the review queue; a click opens Workbench on Review.
final class IslandPanel: NSPanel {
    private let session: AppSession
    private var screenChanges: Task<Void, Never>?

    init(session: AppSession) {
        self.session = session
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
        place()
        screenChanges = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification)
            {
                self?.place()
            }
        }
        orderFrontRegardless()
    }

    deinit { screenChanges?.cancel() }

    override var canBecomeKey: Bool { false }

    private func place() {
        let screen = IslandMetrics.screen
        let metrics = IslandMetrics(screen: screen)
        let content = NSHostingView(
            rootView: IslandContent(session: session, metrics: metrics) { [weak self] in
                self?.ignoresMouseEvents = !$0
            })
        content.sizingOptions = []
        contentView = content
        guard let screen else { return }
        let size = metrics.panelSize
        setFrame(
            NSRect(
                x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width,
                height: size.height), display: true)
    }
}

private struct IslandContent: View {
    let session: AppSession
    let metrics: IslandMetrics
    let takesClicks: (Bool) -> Void

    var body: some View {
        IslandView(state: state, metrics: metrics)
            .contentShape(Rectangle())
            .onTapGesture {
                guard state.takesClicks else { return }
                NSWorkspace.shared.open(SidebarSelection.review.url)
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
