import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

@MainActor private final class Taps {
    var opened: [SidebarSelection] = []
    var stops = 0
    var expanded: [Bool] = []
}

@MainActor struct NotchControlTests {
    private let metrics = NotchMetrics(screen: nil)

    private func show(_ state: NotchState, taps: Taps) async throws -> (HiddenWindow, NotchMouse.Tracker?) {
        let size = metrics.panelSize(expanded: true)
        let window = HiddenWindow(size: size)
        window.contentView = NSHostingView(
            rootView: NotchControl(
                state: state, metrics: metrics, open: { taps.opened.append($0) }, stop: { taps.stops += 1 },
                expand: { taps.expanded.append($0) }
            )
            .frame(width: size.width, height: size.height, alignment: .top))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        return (window, window.contentView.flatMap(Self.tracker(in:)))
    }

    private static func tracker(in view: NSView) -> NotchMouse.Tracker? {
        if let tracker = view as? NotchMouse.Tracker { return tracker }
        return view.subviews.lazy.compactMap(tracker(in:)).first
    }

    private func click(_ tracker: NotchMouse.Tracker, at point: CGPoint, in window: NSWindow) throws {
        let location = tracker.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(
                try #require(
                    NSEvent.mouseEvent(
                        with: type, location: location, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
    }

    @Test func hoveringARecordingGrowsItAndItsStopEndsTheCallWhileTheRestOpensEcho() async throws {
        let taps = Taps()
        let (window, found) = try await show(.recording(since: .now), taps: taps)
        defer { window.orderOut(nil) }
        let tracker = try #require(found)
        let timer = tracker.bounds.size
        #expect(timer.height == metrics.notchHeight && timer.width <= metrics.compactSize.width)

        tracker.mouseEntered(with: NSEvent())
        try await Task.sleep(for: .milliseconds(300))
        #expect(taps.expanded == [true])
        #expect(tracker.bounds.size == metrics.expandedSize)

        let stop = NotchView.stopRect(metrics)
        try click(tracker, at: CGPoint(x: stop.midX, y: stop.midY), in: window)
        #expect(taps.stops == 1 && taps.opened.isEmpty)

        try click(tracker, at: CGPoint(x: 20, y: 10), in: window)
        #expect(taps.stops == 1 && taps.opened == [.calls])

        tracker.mouseExited(with: NSEvent())
        try await Task.sleep(for: .milliseconds(300))
        #expect(taps.expanded == [true, false])
    }

    @Test func aPlainPressOnTheQueueOpensReviewAndNeverStopsAnything() async throws {
        let taps = Taps()
        let (window, found) = try await show(.waiting(machines: ["Pip"]), taps: taps)
        defer { window.orderOut(nil) }
        let tracker = try #require(found)
        #expect(tracker.bounds.width == metrics.compactSize(ear: 0).width)
        let stop = NotchView.stopRect(metrics)
        try click(tracker, at: CGPoint(x: min(stop.midX, tracker.bounds.maxX - 2), y: 4), in: window)
        #expect(taps.opened == [.review] && taps.stops == 0)
    }

    @Test func nothingShownTakesNoMouse() async throws {
        let (window, tracker) = try await show(.idle, taps: Taps())
        defer { window.orderOut(nil) }
        #expect(tracker == nil)
    }
}
