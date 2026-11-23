import SwiftUI

public struct WorkbenchApp: App {
    static let mainWindowID = "main"
    private static let titleBarAndToolbarHeight: CGFloat = 52

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage("zoom") private var zoom = 1.0

    public init() {}

    public var body: some Scene {
        Window("Workbench", id: Self.mainWindowID) {
            switch appDelegate.launch {
            case .ready(let session):
                Group {
                    if session.onboarding.isFinished {
                        WorkbenchView()
                    } else {
                        OnboardingView()
                    }
                }
                .zoomed(Zoom(zoom))
                .background(.pageFill)
                .navigationSubtitle(session.capture.profile.isDemo ? ProfileSwitch.demoLabel : "")
                .environment(session)
                .onOpenURL { url in session.navigation.requested = SidebarSelection(url: url) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await session.crew.notifications.recheck() }
                }
            case .failed(let failure):
                StartupErrorView(failure: failure)
            }
        }
        .commands {
            ZoomCommands()
            if case .ready(let session) = appDelegate.launch { SettingsCommand(navigation: session.navigation) }
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            let visible = context.defaultDisplay.visibleRect
            return WindowPlacement(
                size: CGSize(
                    width: min(WorkbenchView.idealSize.width, visible.width),
                    height: min(WorkbenchView.idealSize.height, visible.height - Self.titleBarAndToolbarHeight)))
        }

        MenuBarExtra {
            switch appDelegate.launch {
            case .ready(let session): MenuBarMenu().environment(session)
            case .failed: Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        } label: {
            switch appDelegate.launch {
            case .ready(let session): MenuBarLabel(session: session)
            case .failed: Image(systemName: "exclamationmark.triangle")
            }
        }
    }
}

extension View {
    func environment(_ session: AppSession) -> some View {
        environment(session.onboarding)
            .environment(session.capture)
            .environment(session.identity)
            .environment(session.team)
            .environment(session.models)
            .environment(session.crew)
            .environment(session.crew.notifications)
            .environment(session.review)
            .environment(session.mochi)
            .environment(session.today)
            .environment(session.reminders)
            .environment(session.morning)
            .environment(session.catalog)
            .environment(session.actions)
            .environment(session.deals)
            .environment(session.workspace)
            .environment(session.memory)
            .environment(session.web)
            .environment(session.claims)
            .environment(session.runs)
            .environment(session.browsers)
            .environment(session.planUsage)
            .environment(session.calls)
            .environment(session.callWatcher)
            .environment(session.playback)
            .environment(session.navigation)
    }
}

private struct SettingsCommand: Commands {
    let navigation: Navigation
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                navigation.openSettings()
                openWindow(id: WorkbenchApp.mainWindowID)
            }
            .keyboardShortcut(",")
        }
    }
}
