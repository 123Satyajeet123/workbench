import SwiftUI

enum SettingsTab: Hashable {
    case general, capture, team, advanced
}

struct SettingsView: View {
    @Environment(Navigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.settingsTab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) { GeneralSettingsView() }
            Tab("Capture", systemImage: "eye", value: SettingsTab.capture) { CaptureSettingsView() }
            Tab("Team", systemImage: "person.3", value: SettingsTab.team) { TeamSettingsView() }
            Tab("Advanced", systemImage: "gauge.with.dots.needle.33percent", value: SettingsTab.advanced) {
                AdvancedSettingsView()
            }
        }
        .frame(width: 640, height: 600)
    }
}
