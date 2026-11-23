import Foundation

/// A place where a fact is shown and acted on. A mark carries it, so the study knows where an answer came from.
enum Surface: String, CaseIterable {
    case today, review, notification, menuBar, island, machinePage
}
