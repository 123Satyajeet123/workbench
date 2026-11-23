import AppKit
import SwiftUI

/// One quiet line that says the data on screen is synthetic, with the one way back.
struct DemoBanner: View {
    let back: () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Text(ProfileSwitch.bannerText).textStyle(.caption, weight: .medium)
            Spacer(minLength: Space.m)
            Button(ProfileSwitch.title(to: .yours), action: back).buttonStyle(.link).textStyle(.caption)
        }
        .padding(.horizontal, Space.m)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(.calloutFill)
        .overlay(alignment: .bottom) { Rectangle().fill(.dividerLine).frame(height: 1) }
        .foregroundStyle(.bodyText)
    }
}

/// Puts the banner under the title bar of every window that has one, now and when a window opens later: the main
/// window and Settings are both covered without either one drawing it.
@MainActor
final class DemoBannerWindows {
    static let accessoryID = NSUserInterfaceItemIdentifier("workbench.demoBanner")

    private let back: @MainActor () -> Void
    private var observer: (any NSObjectProtocol)?

    init(
        center: NotificationCenter = .default, windows: [NSWindow] = NSApp.windows,
        back: @escaping @MainActor () -> Void
    ) {
        self.back = back
        install(on: windows)
        observer = center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) {
            [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.install(on: [window]) }
        }
    }

    func install(on windows: [NSWindow]) {
        for window in windows where window.styleMask.contains(.titled) && !Self.hasBanner(window) {
            let accessory = NSTitlebarAccessoryViewController()
            accessory.identifier = Self.accessoryID
            accessory.layoutAttribute = .bottom
            accessory.view = NSHostingView(rootView: DemoBanner(back: back))
            window.addTitlebarAccessoryViewController(accessory)
        }
    }

    static func hasBanner(_ window: NSWindow) -> Bool {
        window.titlebarAccessoryViewControllers.contains { $0.identifier == accessoryID }
    }
}
