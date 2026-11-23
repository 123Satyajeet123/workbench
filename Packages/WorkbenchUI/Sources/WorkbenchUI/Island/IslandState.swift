import AppKit

/// What the island shows, from what the app already knows. A call being recorded comes first, so consent is always
/// visible; then a machine that is reading. It never shows watched content: only a machine's name.
enum IslandState: Equatable {
    case idle
    case recording(since: Date)
    case reading(machine: String)

    init(recordingSince: Date?, reading: [String]) {
        if let recordingSince {
            self = .recording(since: recordingSince)
        } else if let label = Self.readingLabel(of: reading) {
            self = .reading(machine: label)
        } else {
            self = .idle
        }
    }

    /// One machine by name, several by count. Nil when none reads.
    static func readingLabel(of machines: [String]) -> String? {
        machines.count > 1 ? "\(machines.count) machines" : machines.first
    }

    var isRecording: Bool {
        if case .recording = self { true } else { false }
    }

    /// Only a recording takes a click: it opens the Calls page. Otherwise clicks go to the menu bar below.
    var takesClicks: Bool { isRecording }

    /// The other side of a screen share may see the island only while it shows that a call is recorded. Research 70
    /// measured that a panel with `.none` stays out of a screenshot, and one with `.readOnly` is in it.
    var sharingType: NSWindow.SharingType { isRecording ? .readOnly : .none }
}
