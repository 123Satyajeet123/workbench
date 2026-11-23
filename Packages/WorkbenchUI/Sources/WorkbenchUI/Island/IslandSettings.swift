import Foundation

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

enum IslandKey {
    static let style = "island.style"
    static let shown = "island.shown"
    static let recording = "island.recording"
    static let reading = "island.reading"
    static let review = "island.review"
    static let idle = "island.idle"
}
