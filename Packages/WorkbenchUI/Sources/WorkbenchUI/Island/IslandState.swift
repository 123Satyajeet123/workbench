import Foundation

enum IslandState: Equatable {
    case idle
    case recording(since: Date)
    case reading(machine: String)
    case waiting(count: Int)

    init(recordingSince: Date?, reading: [String], waiting: Int) {
        if let recordingSince {
            self = .recording(since: recordingSince)
        } else if let machine = reading.first {
            self = .reading(machine: reading.count == 1 ? machine : "\(reading.count) machines")
        } else if waiting > 0 {
            self = .waiting(count: waiting)
        } else {
            self = .idle
        }
    }

    var takesClicks: Bool {
        if case .waiting = self { true } else { false }
    }
}
