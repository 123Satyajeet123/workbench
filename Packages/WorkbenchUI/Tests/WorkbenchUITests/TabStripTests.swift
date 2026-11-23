import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

@MainActor private final class Holder: ObservableObject {
    @Published var tabs = PageTabs()
}

private struct Strip: View {
    @ObservedObject var holder: Holder

    var body: some View {
        TabStrip(tabs: $holder.tabs, height: 40).frame(width: 900, height: 40, alignment: .leading)
    }
}

@MainActor struct TabStripTests {
    @Test func draggingATabAlongTheBarMovesItAndAClickStillSelects() async throws {
        guard case .ready(let session) = AppLaunch.start(storeFolder: scratchFolder()) else {
            Issue.record("the app did not start")
            return
        }
        let holder = Holder()
        holder.tabs.openNewTab(.people)
        holder.tabs.openNewTab(.usage)
        let window = HiddenWindow(size: CGSize(width: 900, height: 40))
        window.contentView = NSHostingView(rootView: Strip(holder: holder).environment(session))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))

        func send(_ type: NSEvent.EventType, x: CGFloat) throws {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: CGPoint(x: x, y: 20), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        let width = TabChip.width.upperBound + 1
        let third = 1 + width * 2.5
        try send(.leftMouseDown, x: third)
        for step in 1...10 {
            try send(.leftMouseDragged, x: third - width * 2 * CGFloat(step) / 10)
            try await Task.sleep(for: .milliseconds(16))
        }
        try send(.leftMouseUp, x: third - width * 2)
        try await Task.sleep(for: .milliseconds(200))
        #expect(holder.tabs.tabs.map(\.page) == [.usage, .mochi, .people])

        try send(.leftMouseDown, x: 1 + width * 1.5)
        try send(.leftMouseUp, x: 1 + width * 1.5)
        try await Task.sleep(for: .milliseconds(200))
        #expect(holder.tabs.page == .mochi)
    }
}
