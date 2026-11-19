import Observation

/// A page that another surface, such as the island, asks the main window to show. The window shows it when it
/// opens, or at once when it is open.
@Observable
final class Navigation {
    var requested: SidebarSelection?
}
