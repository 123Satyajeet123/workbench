import AppKit
import SwiftUI

/// The pointer over the island: hover, press and click, with a pointing hand. It works though the panel never
/// becomes key.
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
