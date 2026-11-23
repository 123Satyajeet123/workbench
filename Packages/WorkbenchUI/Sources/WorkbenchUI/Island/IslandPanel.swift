import AppKit
import SwiftUI

/// Shows the island above every window, on the screen with the notch, and updates it when screens change. It never
/// takes the keyboard. It takes the pointer only while the island shows something, and is then as large as the shape,
/// so a click beside the shape goes to the menu bar below. A hover makes the panel tall before the shape expands, and
/// short again after it collapsed.
final class IslandPanel: NSPanel {
    private let presenter = IslandPresenter(metrics: .sample)
    private var screenChanges: Task<Void, Never>?
    private let space: (any SpaceHolding)?

    /// `state` is read where SwiftUI tracks it, so the island follows what it reads. `open` runs on a click, with the
    /// page of what shows. `stop` runs on the Stop button of a recording.
    init(
        state: @escaping (IslandShows) -> IslandState, open: @escaping (SidebarSelection) -> Void,
        stop: @escaping () -> Void, space: (any SpaceHolding)? = IslandSpace()
    ) {
        self.space = space
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
        let content = NSHostingView(
            rootView: IslandRoot(presenter: presenter, state: state, open: open, stop: stop) { [weak self] look in
                self?.ignoresMouseEvents = !look.takesClicks
                self?.sharingType = look.sharingType
                self?.fit()
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
            state: { shows in
                IslandState(
                    recordingSince: session.capture.call?.startedAt,
                    reading: session.crew.machines.filter { $0.phase == .reading }.map {
                        (name: $0.name, page: SidebarSelection.machine($0.machine.id))
                    },
                    needsYou: session.today.needs.map { session.crew.name(ofTask: $0.item.task) },
                    plan: session.models.billing == .plan
                        ? session.planUsage.limits.flatMap { $0.fiveHour ?? $0.week } : nil,
                    shows: shows)
            },
            open: { NSWorkspace.shared.open($0.url) }, stop: session.capture.stopCall)
    }

    deinit { screenChanges?.cancel() }

    override var canBecomeKey: Bool { false }

    /// Fits the island to the notch screen and hands it to its own space. With no notch screen, nothing shows.
    private func place() {
        guard let screen = IslandMetrics.screen, let metrics = IslandMetrics(screen: screen) else {
            orderOut(nil)
            return
        }
        presenter.place(metrics)
        fit()
        orderFrontRegardless()
        space?.hold(self)
    }

    /// The frame changes only when the screen's geometry or the panel's height does, and the view stays.
    private func fit() {
        guard let screen = IslandMetrics.screen else { return }
        let frame = presenter.metrics.panelFrame(on: screen.frame, isTall: presenter.isTall)
        if frame != self.frame { setFrame(frame, display: true) }
    }
}

/// What the panel takes from what the island shows.
private struct PanelLook: Equatable {
    var takesClicks: Bool
    var sharingType: NSWindow.SharingType
    var isTall: Bool
}

/// Hover peeks, click acts: a hover expands the shape to its detail line, and a click opens the page of what shows.
private struct IslandRoot: View {
    let presenter: IslandPresenter
    let state: (IslandShows) -> IslandState
    let open: (SidebarSelection) -> Void
    let stop: () -> Void
    let didChange: (PanelLook) -> Void
    @AppStorage(IslandKey.recording) private var showsRecording = true
    @AppStorage(IslandKey.reading) private var showsReading = true
    @AppStorage(IslandKey.needsYou) private var showsNeedsYou = true
    @AppStorage(IslandKey.idle) private var idle = IslandIdle.nothing
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current = state(
            IslandShows(
                recording: showsRecording, reading: showsReading, needsYou: showsNeedsYou, plan: idle == .planRing))
        let look = PanelLook(
            takesClicks: presenter.content.takesClicks, sharingType: current.sharingType, isTall: presenter.isTall)
        IslandView(presenter: presenter, isPressed: isPressed)
            .overlay {
                if look.takesClicks {
                    IslandMouse(hover: hover, press: press, click: click).onDisappear { hover(false) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: look, initial: true) { _, look in didChange(look) }
            .onChange(of: current, initial: true) { _, state in presenter.show(state, reduceMotion: reduceMotion) }
    }

    private func hover(_ isHovered: Bool) {
        presenter.hover(isHovered, reduceMotion: reduceMotion)
    }

    private func press(_ isDown: Bool) {
        isPressed = isDown
        if isDown { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
    }

    private func click(at point: CGPoint) {
        let content = presenter.content
        if presenter.isDetailVisible, content.isRecording, presenter.metrics.stopRect.contains(point) {
            stop()
        } else if let page = content.page {
            open(page)
        }
    }
}
