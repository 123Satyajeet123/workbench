import Foundation
import WorkbenchCore

struct IslandShows: Equatable {
    var recording = true
    var reading = true
    var review = true
}

enum IslandState: Equatable {
    case idle
    case plan(PlanLimits.Window)
    case recording(since: Date)
    case offer(String)
    case reading(names: [String], page: SidebarSelection)
    case waiting(machines: [String])

    init(
        recordingSince: Date?, offering: String? = nil, reading: [(name: String, page: SidebarSelection)],
        waiting: [String],
        plan: PlanLimits.Window? = nil, shows: IslandShows = IslandShows()
    ) {
        if shows.recording, let recordingSince {
            self = .recording(since: recordingSince)
        } else if shows.recording, let offering {
            self = .offer(offering)
        } else if shows.reading, let first = reading.first {
            self = .reading(names: reading.map(\.name), page: reading.count == 1 ? first.page : .crew)
        } else if shows.review, !waiting.isEmpty {
            self = .waiting(machines: waiting)
        } else if let plan {
            self = .plan(plan)
        } else {
            self = .idle
        }
    }

    var takesClicks: Bool { self != .idle }

    var isOffer: Bool {
        if case .offer = self { true } else { false }
    }

    var page: SidebarSelection? {
        switch self {
        case .idle: nil
        case .plan: .usage
        case .recording, .offer: .calls
        case .reading(_, let page): page
        case .waiting: .mochi
        }
    }

    var detail: String {
        switch self {
        case .idle: ""
        case .plan(let window): "Claude plan · \(window.line)"
        case .recording: "Recording a call"
        case .offer(let service): "\(service) call"
        case .reading(let names, _):
            names.count == 1 ? "\(names[0]) is reading" : "\(names.formatted(.list(type: .and))) are reading"
        case .waiting(let machines):
            waitingDetail(machines)
        }
    }

    private func waitingDetail(_ machines: [String]) -> String {
        let counts = Dictionary(machines.map { ($0, 1) }, uniquingKeysWith: +)
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        if machines.count == 1 { return "\(machines[0]) asks: is this right?" }
        if counts.count == 1 { return "\(machines.count) to review from \(counts[0].key)" }
        return "\(machines.count) to review · " + counts.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }
}
