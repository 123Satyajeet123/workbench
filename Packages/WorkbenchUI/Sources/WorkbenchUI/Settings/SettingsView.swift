import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case general, capture, team, notifications, advanced
}

struct SettingsView: View {
    @Environment(Navigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.settingsTab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) { GeneralSettingsView() }
            Tab("Capture", systemImage: "eye", value: SettingsTab.capture) { CaptureSettingsView() }
            Tab("Team", systemImage: "person.3", value: SettingsTab.team) { TeamSettingsView() }
            Tab("Notifications", systemImage: "bell", value: SettingsTab.notifications) {
                NotificationSettingsView()
            }
            Tab("Advanced", systemImage: "gauge.with.dots.needle.33percent", value: SettingsTab.advanced) {
                UsagePage()
            }
        }
        .frame(width: 640, height: 600)
        .background { CloseOnEscape() }
    }
}

struct CloseOnEscape: View {
    var body: some View {
        Button("Close") { NSApp.keyWindow?.performClose(nil) }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
