import Observation

/// A page that another surface, such as the island or the menu bar, asks the main window to show. The window shows it
/// when it opens, or at once when it is open. Also the section the settings page shows, so a link can open one.
@Observable
final class Navigation {
    var requested: SidebarSelection?
    /// The fact the person chose in the menu bar. Mochi's page opens it in the inspector.
    var requestedFact: Int64?
    var settingsSection = SettingsSection.general

    /// Opens Mochi's page with `fact` in the inspector.
    func show(fact: Int64) {
        requested = .mochi
        requestedFact = fact
    }

    func openSettings(_ section: SettingsSection = .general) {
        settingsSection = section
        requested = .settings
    }
}
