import Foundation

/// What the island shows when nothing happens.
enum IslandIdle: String, CaseIterable, Identifiable {
    case nothing, planRing

    var id: Self { self }

    var title: String {
        switch self {
        case .nothing: "Nothing"
        case .planRing: "Claude plan ring"
        }
    }
}

/// How alerts show: around the notch (the island), or as a pop-up at the top right. Both show the same moments.
enum AlertStyle: String, CaseIterable, Identifiable {
    case notch, popup

    var id: Self { self }

    static func current(in defaults: UserDefaults = .standard) -> AlertStyle {
        defaults.string(forKey: IslandKey.style).flatMap(AlertStyle.init(rawValue:)) ?? .notch
    }

    var title: String {
        switch self {
        case .notch: "Notch"
        case .popup: "Pop-up"
        }
    }
}

/// Where Settings keeps what the island shows.
enum IslandKey {
    static let style = "island.style"
    static let recording = "island.recording"
    static let reading = "island.reading"
    static let needsYou = "island.review"
    static let idle = "island.idle"
}
