import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

@MainActor private final class FoldState: ObservableObject {
    @Published var shown = 0
    @Published var hidden = 0
    @Published var innerTaps = 0
}

private struct FoldWithButton: View {
    @ObservedObject var state: FoldState

    var body: some View {
        Fold {
            Text("Inside").onAppear { state.shown += 1 }.onDisappear { state.hidden += 1 }
        } label: {
            HStack {
                Text("Settings")
                Spacer()
                Button("Inner") { state.innerTaps += 1 }.buttonStyle(.plain)
            }
        }
        .frame(width: 300, height: 60, alignment: .topLeading)
        .transaction { $0.animation = nil }
    }
}

@MainActor struct FoldTests {
    @Test func theTitleOpensAndClosesTheFoldWhileAButtonInItKeepsItsOwnClick() async throws {
        let state = FoldState()
        let window = NSWindow(
            contentRect: CGRect(x: 200, y: 200, width: 300, height: 60), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.contentView = NSHostingView(rootView: FoldWithButton(state: state))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        func waitUntil(_ done: () -> Bool) async throws {
            let clock = ContinuousClock()
            let end = clock.now + .seconds(5)
            while !done(), clock.now < end { try await Task.sleep(for: .milliseconds(20)) }
        }

        func click(x: CGFloat) async throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(
                    NSEvent.mouseEvent(
                        with: type, location: CGPoint(x: x, y: 50), modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
        }

        try await waitUntil { window.contentView?.fittingSize.height ?? 0 > 0 }
        try await click(x: 40)
        try await waitUntil { state.shown == 1 }
        #expect(state.shown == 1)
        try await click(x: 5)
        try await waitUntil { state.hidden == 1 }
        #expect(state.hidden == 1)
        try await click(x: 5)
        try await waitUntil { state.shown == 2 }
        #expect(state.shown == 2)
        try await click(x: 285)
        try await waitUntil { state.innerTaps == 1 }
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.innerTaps == 1 && state.hidden == 1)
    }
}
