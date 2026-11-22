import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

@MainActor private final class FoldState: ObservableObject {
    @Published var shown = 0
    @Published var innerTaps = 0
}

private struct FoldWithButton: View {
    @ObservedObject var state: FoldState

    var body: some View {
        Fold {
            Text("Inside").onAppear { state.shown += 1 }
        } label: {
            HStack {
                Text("Settings")
                Spacer()
                Button("Inner") { state.innerTaps += 1 }.buttonStyle(.plain)
            }
        }
        .frame(width: 300, height: 60, alignment: .topLeading)
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
        try await Task.sleep(for: .milliseconds(300))

        func click(x: CGFloat) async throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(
                    NSEvent.mouseEvent(
                        with: type, location: CGPoint(x: x, y: 50), modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
            try await Task.sleep(for: .milliseconds(300))
        }

        try await click(x: 40)
        #expect(state.shown == 1)
        try await click(x: 5)
        try await click(x: 5)
        #expect(state.shown == 2)
        try await click(x: 285)
        #expect(state.innerTaps == 1 && state.shown == 2)
    }
}
