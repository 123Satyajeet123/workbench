import Observation

/// A page that another surface, such as the island or the menu bar, asks the main window to show. The window shows it
/// when it opens, or at once when it is open. Also the tab Settings shows, so a link can open Settings › Advanced.
@Observable
final class Navigation {
    var requested: SidebarSelection?
    /// The fact the person chose in the menu bar. Today opens it in the inspector.
    var requestedFact: Int64?
    var settingsTab = SettingsTab.general

    /// Opens Today with `fact` in the inspector.
    func show(fact: Int64) {
        requested = .day
        requestedFact = fact
    }

    var settingsSection = SettingsSection.general

    func openSettings(_ section: SettingsSection = .general) {
        settingsSection = section
        requested = .settings
    }
}
