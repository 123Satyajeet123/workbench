import AppKit
import SwiftUI

extension View {
    /// Keeps a page in an editor safe while its view lives: it is shown again from the store when the view appears and
    /// when the app comes back, and saved when the view goes, when the app goes to the back and when the app quits.
    func keepsSaved(_ editor: @escaping () -> PageEditorController?, refresh: @escaping () -> Void) -> some View {
        onAppear(perform: refresh)
            .onDisappear { Task { await editor()?.flush() } }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                Task { await editor()?.flush() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                editor()?.flushBeforeQuit()
            }
    }
}

extension EditorHost {
    /// A link the person followed in the page: the system opens web and mail addresses, and nothing else.
    static func openLink(_ address: String) {
        if let url = URL(string: address), ["http", "https", "mailto"].contains(url.scheme) {
            NSWorkspace.shared.open(url)
        }
    }
}
