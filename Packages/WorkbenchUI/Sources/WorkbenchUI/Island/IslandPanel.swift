import AppKit
import SwiftUI

/// Shows the island above every window, on the screen with the notch, and updates it when screens change. It never
/// takes the keyboard, and takes a click only while a call is recorded.
final class IslandPanel: NSPanel {
    private let presenter = IslandPresenter(metrics: .sample)
    private var screenChanges: Task<Void, Never>?

    /// `state` is read where SwiftUI tracks it, so the island follows what it reads. `open` runs on a click.
    init(state: @escaping () -> IslandState, open: @escaping () -> Void) {
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
        sharingType = .none
        let content = ClickableHostingView(
            rootView: IslandRoot(presenter: presenter, state: state, open: open) { [weak self] state in
                self?.ignoresMouseEvents = !state.takesClicks
                self?.sharingType = state.sharingType
            })
        content.sizingOptions = []
        contentView = content
        place()
        screenChanges = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification)
            {
                self?.place()
            }
        }
    }

    convenience init(session: AppSession) {
        self.init(
            state: {
                IslandState(
                    recordingSince: session.capture.call?.startedAt,
                    reading: session.crew.machines.filter { $0.phase == .reading }.map(\.name))
            },
            open: { NSWorkspace.shared.open(SidebarSelection.calls.url) })
    }

    deinit { screenChanges?.cancel() }

    override var canBecomeKey: Bool { false }

    /// Fits the island to the notch screen. The panel's frame changes only when the screen's geometry does, and the
    /// view stays. With no notch screen, nothing shows.
    private func place() {
        guard let screen = IslandMetrics.screen, let metrics = IslandMetrics(screen: screen) else {
            orderOut(nil)
            return
        }
        presenter.place(metrics)
        let frame = metrics.panelFrame(on: screen.frame)
        if frame != self.frame { setFrame(frame, display: true) }
        orderFrontRegardless()
    }
}

/// A click on the island works at once, though the panel never becomes key.
private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct IslandRoot: View {
    let presenter: IslandPresenter
    let state: () -> IslandState
    let open: () -> Void
    let didChange: (IslandState) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current = state()
        IslandView(presenter: presenter)
            .contentShape(Rectangle())
            .onTapGesture { if current.takesClicks { open() } }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: current, initial: true) { _, state in
                didChange(state)
                presenter.show(state, reduceMotion: reduceMotion)
            }
    }
}
