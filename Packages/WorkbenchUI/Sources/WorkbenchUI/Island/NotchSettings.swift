import Foundation

enum NotchIdle: String, CaseIterable, Identifiable {
    case nothing, planRing

    var id: Self { self }

    var title: String {
        switch self {
        case .nothing: "Nothing"
        case .planRing: "Claude plan ring"
        }
    }
}

enum NotchKey {
    static let shown = "island.shown"
    /// The hover notch is off until a person turns it on, and while it is off the Island shows instead.
    static let shownByDefault = false
    static let recording = "island.recording"
    static let reading = "island.reading"
    static let review = "island.review"
    static let idle = "island.idle"
}
