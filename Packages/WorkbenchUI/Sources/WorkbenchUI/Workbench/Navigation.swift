import Observation

@Observable
final class Navigation {
    var requested: SidebarSelection?
    var settingsTab = SettingsTab.general
}
