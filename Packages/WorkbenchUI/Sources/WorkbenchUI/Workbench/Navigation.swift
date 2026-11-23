import Observation

@Observable
final class Navigation {
    var requested: SidebarSelection?
    var settingsSection = SettingsSection.general

    func openSettings(_ section: SettingsSection = .general) {
        settingsSection = section
        requested = .settings
    }
}
