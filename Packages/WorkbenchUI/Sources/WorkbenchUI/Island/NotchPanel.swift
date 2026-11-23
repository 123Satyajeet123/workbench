import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    private let session: AppSession
    private var screenChanges: Task<Void, Never>?
    private var shrinking: Task<Void, Never>?
    private var metrics = NotchMetrics(screen: nil)

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

    deinit {
        screenChanges?.cancel()
        shrinking?.cancel()
    }

    override var canBecomeKey: Bool { false }

    private func place() {
        metrics = NotchMetrics(screen: NotchMetrics.screen)
        let content = NSHostingView(
            rootView: NotchContent(
                session: session, metrics: metrics,
                takesClicks: { [weak self] in self?.ignoresMouseEvents = !$0 },
                expand: { [weak self] in self?.expand($0) }))
        content.sizingOptions = []
        contentView = content
        resize(expanded: false)
    }

    private func expand(_ expanded: Bool) {
        shrinking?.cancel()
        guard !expanded else { return resize(expanded: true) }
        shrinking = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.resize(expanded: false)
        }
    }

    private func resize(expanded: Bool) {
        guard let screen = NotchMetrics.screen else { return }
        let size = metrics.panelSize(expanded: expanded)
        setFrame(
            NSRect(
                x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width,
                height: size.height), display: true)
    }
}

private struct NotchContent: View {
    let session: AppSession
    let metrics: NotchMetrics
    let takesClicks: (Bool) -> Void
    let expand: (Bool) -> Void
    @AppStorage(NotchKey.shown) private var shown = NotchKey.shownByDefault
    @AppStorage(NotchKey.recording) private var showsRecording = true
    @AppStorage(NotchKey.reading) private var showsReading = true
    @AppStorage(NotchKey.review) private var showsReview = true
    @AppStorage(NotchKey.idle) private var idle = NotchIdle.nothing

    var body: some View {
        NotchControl(
            state: state, metrics: metrics, open: { NSWorkspace.shared.open($0.url) },
            stop: session.capture.stopCall, expand: expand
        )
        .padding(.top, metrics.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: state.takesClicks, initial: true) { _, takes in takesClicks(takes) }
    }

    private var state: NotchState {
        guard shown else { return .idle }
        let limits = idle == .planRing && session.models.billing == .plan ? session.planUsage.limits : nil
        return NotchState(
            recordingSince: session.capture.call?.startedAt,
            reading: session.crew.machines.filter { $0.phase == .reading }.map {
                (name: $0.name, page: SidebarSelection.machine($0.machine.id))
            },
            waiting: session.review.items.map(session.review.name(of:)),
            plan: limits.flatMap { $0.fiveHour ?? $0.week },
            shows: NotchShows(recording: showsRecording, reading: showsReading, review: showsReview))
    }
}
