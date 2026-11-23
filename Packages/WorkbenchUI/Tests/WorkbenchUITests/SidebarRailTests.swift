import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

@MainActor private final class Picked: ObservableObject {
    @Published var page = SidebarSelection.day
}

private struct Rail: View {
    @ObservedObject var picked: Picked

    var body: some View {
        Sidebar(selection: $picked.page, titleBar: 40, toggleLeading: 80, isRail: true, toggle: {})
            .frame(width: WorkbenchView.railWidth, height: 640)
    }
}

@MainActor struct SidebarRailTests {
    @Test func clickingDownTheRailOpensEveryPageAndMachineInTheSidebarsOrder() async throws {
        guard case .ready(let session) = AppLaunch.start(storeFolder: scratchFolder()) else {
            Issue.record("the app did not start")
            return
        }
        let pip = try #require(session.crew.team)
        let picked = Picked()
        picked.page = .deals
        let window = HiddenWindow(size: CGSize(width: WorkbenchView.railWidth, height: 640))
        window.contentView = NSHostingView(rootView: Rail(picked: picked).environment(session))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(400))

        var opened: [String] = []
        let height = window.contentView!.bounds.height
        for y in stride(from: height - 40, to: 80, by: -12) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(
                    NSEvent.mouseEvent(
                        with: type, location: CGPoint(x: WorkbenchView.railWidth / 2, y: y), modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
            try await Task.sleep(for: .milliseconds(60))
            if let sheet = window.attachedSheet {
                let escape = try #require(
                    NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber,
                        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                        keyCode: 53))
                sheet.sendEvent(escape)
                if opened.last != "add" { opened.append("add") }
                try await Task.sleep(for: .milliseconds(400))
            } else if opened.last != "\(picked.page)" {
                opened.append("\(picked.page)")
            }
        }
        let pages: [SidebarSelection] = [.day, .people, .projects, .calls, .mochi, .crew, .machine(pip.machine.id)]
        let expected =
            ["\(SidebarSelection.deals)"] + pages.map { "\($0)" } + [
                "add", "\(SidebarSelection.review)", "\(SidebarSelection.usage)",
            ]
        #expect(opened == expected)
    }
}
