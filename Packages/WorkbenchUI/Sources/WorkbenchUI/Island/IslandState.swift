import AppKit
import WorkbenchCore

/// What the island shows, from what the app already knows and what the person chose to see. A call being recorded
/// comes first, so consent is always visible; then a machine that is reading; then the lines on Today that need the
/// person; then, when nothing happens, the Claude plan. It never shows watched content: only names and counts.
enum IslandState: Equatable {
    case idle
    case plan(PlanLimits.Window)
    case recording(since: Date)
    case reading(names: [String], page: SidebarSelection)
    /// The name of the machine behind each line on Today that needs the person.
    case needsYou(machines: [String])

    init(
        recordingSince: Date?, reading: [(name: String, page: SidebarSelection)], needsYou: [String],
        plan: PlanLimits.Window? = nil, shows: IslandShows = IslandShows()
    ) {
        if shows.recording, let recordingSince {
            self = .recording(since: recordingSince)
        } else if shows.reading, let first = reading.first {
            self = .reading(names: reading.map(\.name), page: reading.count == 1 ? first.page : .crew)
        } else if shows.needsYou, !needsYou.isEmpty {
            self = .needsYou(machines: needsYou)
        } else if shows.plan, let plan {
            self = .plan(plan)
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

    /// Whatever shows takes a click and opens its page. Idle, clicks go to the menu bar below.
    var takesClicks: Bool { self != .idle }

    var page: SidebarSelection? {
        switch self {
        case .idle: nil
        case .plan: .usage
        case .recording: .calls
        case .reading(_, let page): page
        case .needsYou: .day
        }
    }

    /// The line that a hover shows under the notch.
    var detail: String {
        switch self {
        case .idle: ""
        case .plan(let window): "Claude plan · \(window.line)"
        case .recording: "Recording a call"
        case .reading(let names, _):
            names.count == 1 ? "\(names[0]) is reading" : "\(names.formatted(.list(type: .and))) are reading"
        case .needsYou(let machines): Self.needsYouDetail(machines)
        }
    }

    /// The other side of a screen share may see the island only while it shows that a call is recorded. Research 70
    /// measured that a panel with `.none` stays out of a screenshot, and one with `.readOnly` is in it.
    var sharingType: NSWindow.SharingType { isRecording ? .readOnly : .none }

    private static func needsYouDetail(_ machines: [String]) -> String {
        let counts = Dictionary(machines.map { ($0, 1) }, uniquingKeysWith: +)
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        if counts.count == 1 { return "\(machines.count) need you, from \(counts[0].key)" }
        return "\(machines.count) need you · " + counts.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }
}

/// What the person chose in Settings for the island to show.
struct IslandShows: Equatable {
    var recording = true
    var reading = true
    var needsYou = true
    var plan = false
}
