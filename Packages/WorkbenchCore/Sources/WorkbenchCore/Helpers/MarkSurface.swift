import Foundation

/// Where a person made a mark. Every event of a person that closes, reopens, withdraws, hides, snoozes, unhides or
/// hands off a fact records one, so the trust measures can tell a mark made on a list from one made on a notification.
public enum MarkSurface: String, CaseIterable, Sendable {
    case today
    case review
    case notification
    case menuBar = "menu_bar"
    case island
    case machinePage = "machine_page"
    case deals
}
