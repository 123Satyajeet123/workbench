import AppKit
import SwiftUI

struct NotchControl: View {
    let state: NotchState
    let metrics: NotchMetrics
    let open: (SidebarSelection) -> Void
    let stop: () -> Void
    var expand: (Bool) -> Void = { _ in }
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        NotchView(state: state, metrics: metrics, isExpanded: isExpanded, isPressed: isPressed)
            .overlay {
                if state.takesClicks { NotchMouse(hover: { isHovered = $0 }, press: press, click: click) }
            }
            .onChange(of: isExpanded) { _, expanded in expand(expanded) }
            .onChange(of: state.takesClicks) { _, takes in if !takes { isHovered = false } }
    }

    private var isExpanded: Bool { isHovered && state.takesClicks }

    private func press(_ down: Bool) {
        isPressed = down
        if down { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
    }

    private func click(at point: CGPoint) {
        if isExpanded, case .recording = state, NotchView.stopRect(metrics).contains(point) {
            stop()
        } else if let page = state.page {
            open(page)
        }
    }
}

struct NotchMouse: NSViewRepresentable {
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
