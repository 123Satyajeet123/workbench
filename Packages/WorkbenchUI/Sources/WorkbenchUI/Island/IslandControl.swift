import AppKit
import SwiftUI

struct IslandControl: View {
    let state: IslandState
    let metrics: IslandMetrics
    let open: (SidebarSelection) -> Void
    let stop: () -> Void
    var record: () -> Void = {}
    var dismiss: () -> Void = {}
    var expand: (Bool) -> Void = { _ in }
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var isAnnouncing = false

    var body: some View {
        IslandView(state: state, metrics: metrics, isExpanded: isExpanded, isPressed: isPressed)
            .overlay {
                if state.takesClicks { IslandMouse(hover: { isHovered = $0 }, press: press, click: click) }
            }
            .onChange(of: isExpanded) { _, expanded in expand(expanded) }
            .onChange(of: state.takesClicks) { _, takes in if !takes { isHovered = false } }
            .task(id: state.isOffer) {
                isAnnouncing = state.isOffer
                guard isAnnouncing else { return }
                try? await Task.sleep(for: .seconds(Self.announceFor))
                isAnnouncing = false
            }
    }

    static let announceFor: Double = 10

    private var isExpanded: Bool { (isHovered || isAnnouncing) && state.takesClicks }

    private func press(_ down: Bool) {
        isPressed = down
        if down { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
    }

    private func click(at point: CGPoint) {
        if isExpanded, case .recording = state, IslandView.stopRect(metrics).contains(point) {
            stop()
        } else if isExpanded, state.isOffer, IslandView.stopRect(metrics).contains(point) {
            record()
        } else if isExpanded, state.isOffer, IslandView.notNowRect(metrics).contains(point) {
            dismiss()
        } else if let page = state.page {
            open(page)
        }
    }
}

struct IslandMouse: NSViewRepresentable {
    let hover: (Bool) -> Void
    let press: (Bool) -> Void
    let click: (CGPoint) -> Void

    func makeNSView(context: Context) -> Tracker { Tracker() }

    func updateNSView(_ view: Tracker, context: Context) {
        view.hover = hover
        view.press = press
        view.click = click
    }

    final class Tracker: NSView {
        var hover: (Bool) -> Void = { _ in }
        var press: (Bool) -> Void = { _ in }
        var click: (CGPoint) -> Void = { _ in }

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) { hover(true) }
        override func mouseExited(with event: NSEvent) { hover(false) }
        override func mouseDown(with event: NSEvent) { press(true) }

        override func mouseUp(with event: NSEvent) {
            press(false)
            let point = convert(event.locationInWindow, from: nil)
            if bounds.contains(point) { click(point) }
        }
    }
}
