import SwiftUI

struct MenuBarMenu: View {
    @Environment(CaptureSettings.self) private var capture
    @Environment(Crew.self) private var crew
    @Environment(TodayModel.self) private var today
    @Environment(ReviewModel.self) private var review
    @Environment(Navigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let needs = MenuBarNeeds(today: today, review: review)
        Text(
            MenuBarStatus.line(
                capture: capture.status, reading: crew.machines.filter { $0.phase == .reading }.map(\.name)))
        if let problem = capture.backgroundProblem { Text(problem) }
        if needs.count > 0 {
            Divider()
            Text("Needs you (\(needs.count))")
            ForEach(needs.top) { need in
                Button(need.title) { openWorkbench(on: need) }
            }
        }
        Divider()
        Button("Open Workbench") { openWorkbench() }
        Divider()
        CallMenu()
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

    private func openWorkbench(on need: MenuNeed? = nil) {
        if let need { navigation.show(fact: need.id) }
        openWindow(id: WorkbenchApp.mainWindowID)
        NSApp.activate()
    }
}
