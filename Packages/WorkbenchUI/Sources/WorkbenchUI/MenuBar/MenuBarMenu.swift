import SwiftUI

struct MenuBarMenu: View {
    @Environment(CaptureSettings.self) private var capture
    @Environment(\.openWindow) private var openWindow
    @Environment(Navigation.self) private var navigation

    var body: some View {
        Text("Capture \(capture.status.title.lowercased())")
        if let problem = capture.backgroundProblem { Text(problem) }
        Button("Open Workbench") {
            openWindow(id: WorkbenchApp.mainWindowID)
            NSApp.activate()
        }
        Divider()
        CallMenu()
        Divider()
        Button(capture.mode == .paused ? "Resume" : "Pause for 1 hour") {
            capture.mode = capture.mode == .paused ? .on : .paused
        }
        Toggle(
            "Private mode",
            isOn: Binding {
                capture.mode == .privateHour
            } set: {
                capture.mode = $0 ? .privateHour : .on
            })
        Divider()
        Button("Settings…") {
            navigation.openSettings()
            openWindow(id: WorkbenchApp.mainWindowID)
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button("Quit Workbench") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
