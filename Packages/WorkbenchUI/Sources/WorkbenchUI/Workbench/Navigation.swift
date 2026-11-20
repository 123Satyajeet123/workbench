import Observation

/// A page that another surface, such as the island, asks the main window to show. The window shows it when it
/// opens, or at once when it is open. Also the tab Settings shows, so a link can open Settings › Advanced.
@Observable
final class Navigation {
    var requested: SidebarSelection?
    var settingsTab = SettingsTab.general
}
