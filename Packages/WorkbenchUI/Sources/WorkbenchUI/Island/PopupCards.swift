import Foundation
import WorkbenchCore

enum PopupCard: Equatable, Identifiable {
    case recording(label: String, since: Date)
    case offer(service: String)
    case meeting(Meeting)

    var id: String {
        switch self {
        case .recording: "recording"
        case .offer: "offer"
        case .meeting(let meeting): "meeting:\(meeting.id)"
        }
    }
}

enum PopupCards {
    static let joinBefore: TimeInterval = 60
    static let joinAfter: TimeInterval = 5 * 60

    /// What the pop-up shows of the alert state: only a call, recorded or offered. A recording is always shown, so a
    /// call being recorded stays visible.
    static let shows = IslandShows(recording: true, reading: false, needsYou: false, plan: false)

    /// The cards of the alert state, then a Join card for each meeting with a link from a minute before it starts.
    /// `label` names the call being recorded.
    static func make(
        alert: IslandState, label: String, meetings: [Meeting], dismissed: Set<String>, now: Date
    ) -> [PopupCard] {
        var cards: [PopupCard] = []
        switch alert {
        case .recording(let since): cards.append(.recording(label: label, since: since))
        case .offer(let service): cards.append(.offer(service: service))
        case .idle, .plan, .reading, .needsYou: break
        }
        let due = meetings.filter { meeting in
            meeting.joinURL != nil && !dismissed.contains(PopupCard.meeting(meeting).id)
                && now >= meeting.start.addingTimeInterval(-joinBefore)
                && now < meeting.start.addingTimeInterval(joinAfter)
        }
        return cards + due.sorted { $0.start < $1.start }.map(PopupCard.meeting)
    }

    static func when(_ meeting: Meeting, at now: Date) -> String {
        let minutes = Int((meeting.start.timeIntervalSince(now) / 60).rounded())
        if minutes > 0 { return "Starts in \(minutes) min" }
        if minutes == 0 { return "Starting now" }
        return "Started \(-minutes) min ago"
    }
}
