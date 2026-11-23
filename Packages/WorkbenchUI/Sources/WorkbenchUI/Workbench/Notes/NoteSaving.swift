import AppKit
import SwiftUI

extension View {
    /// Keeps a note safe while its view lives: it is drawn again from the store when the view appears and when the app
    /// comes back, and saved when the view goes, when the app goes to the back and when the app quits.
    func keepsSaved(_ editor: NoteEditorModel, reconcile: @escaping () -> Void) -> some View {
        onAppear(perform: reconcile)
            .onDisappear { Task { await editor.flush() } }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                reconcile()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                Task { await editor.flush() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                editor.saveBeforeQuit()
            }
    }
}
