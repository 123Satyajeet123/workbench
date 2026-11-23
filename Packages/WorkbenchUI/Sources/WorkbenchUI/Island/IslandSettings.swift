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

/// Where Settings keeps what the island shows.
enum IslandKey {
    static let recording = "island.recording"
    static let reading = "island.reading"
    static let needsYou = "island.review"
    static let idle = "island.idle"
}
