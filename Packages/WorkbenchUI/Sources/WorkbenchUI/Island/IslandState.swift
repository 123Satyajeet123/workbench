import Foundation

/// What the island shows, from what the app already knows. A call being recorded comes first, so consent is always
/// visible; then a machine that is reading; then how many items wait for the founder. It never shows watched content:
/// only a machine's name and a count.
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

    /// Only an island that offers something takes a click; otherwise clicks go to the menu bar below it.
    var takesClicks: Bool {
        if case .waiting = self { true } else { false }
    }
}
