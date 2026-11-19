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
                .environment(session)
            case .failed(let failure):
                StartupErrorView(failure: failure)
            }
        }
        .commands { ZoomCommands() }
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
            case .ready(let session): MenuBarIcon(capture: session.capture)
            case .failed: Image(systemName: "exclamationmark.triangle")
            }
        }

        Settings {
            if case .ready(let session) = appDelegate.launch {
                SettingsView().zoomed(Zoom(zoom)).environment(session)
            }
        }
    }
}

extension View {
    /// Puts every model of the session in the environment.
    func environment(_ session: AppSession) -> some View {
        environment(session.onboarding)
            .environment(session.capture)
            .environment(session.identity)
            .environment(session.team)
            .environment(session.models)
            .environment(session.crew)
            .environment(session.review)
            .environment(session.mochi)
            .environment(session.reminders)
            .environment(session.catalog)
            .environment(session.runs)
    }
}
