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

enum IslandKey {
    static let shown = "island.shown"
    static let recording = "island.recording"
    static let reading = "island.reading"
    static let review = "island.review"
    static let idle = "island.idle"
}
