import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

@MainActor private final class Taps {
    var opened: [SidebarSelection] = []
    var stops = 0
    var records = 0
    var dismissals = 0
    var expanded: [Bool] = []
}

@MainActor struct IslandControlTests {
    private let metrics = IslandMetrics(screen: nil)

    private func show(_ state: IslandState, taps: Taps) async throws -> (HiddenWindow, IslandMouse.Tracker?) {
        let size = metrics.panelSize(expanded: true)
        let window = HiddenWindow(size: size)
        window.contentView = NSHostingView(
            rootView: IslandControl(
                state: state, metrics: metrics, open: { taps.opened.append($0) }, stop: { taps.stops += 1 },
                record: { taps.records += 1 }, dismiss: { taps.dismissals += 1 },
                expand: { taps.expanded.append($0) }
            )
            .frame(width: size.width, height: size.height, alignment: .top))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        return (window, window.contentView.flatMap(Self.tracker(in:)))
    }

    private static func tracker(in view: NSView) -> IslandMouse.Tracker? {
        if let tracker = view as? IslandMouse.Tracker { return tracker }
        return view.subviews.lazy.compactMap(tracker(in:)).first
    }

    private func click(_ tracker: IslandMouse.Tracker, at point: CGPoint, in window: NSWindow) throws {
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

        let stop = IslandView.stopRect(metrics)
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
        let stop = IslandView.stopRect(metrics)
        try click(tracker, at: CGPoint(x: min(stop.midX, tracker.bounds.maxX - 2), y: 4), in: window)
        #expect(taps.opened == [.mochi] && taps.stops == 0)
    }

    @Test func anOfferedCallOpensOnItsOwnWithRecordAndNotNow() async throws {
        let taps = Taps()
        let (window, found) = try await show(.offer("Zoom"), taps: taps)
        defer { window.orderOut(nil) }
        let tracker = try #require(found)
        #expect(taps.expanded == [true] && tracker.bounds.size == metrics.expandedSize)

        let notNow = IslandView.notNowRect(metrics)
        try click(tracker, at: CGPoint(x: notNow.midX, y: notNow.midY), in: window)
        let record = IslandView.stopRect(metrics)
        try click(tracker, at: CGPoint(x: record.midX, y: record.midY), in: window)
        try click(tracker, at: CGPoint(x: 20, y: 10), in: window)
        #expect(taps.dismissals == 1 && taps.records == 1 && taps.stops == 0 && taps.opened == [.calls])
    }

    @Test func nothingShownTakesNoMouse() async throws {
        let (window, tracker) = try await show(.idle, taps: Taps())
        defer { window.orderOut(nil) }
        #expect(tracker == nil)
    }
}
