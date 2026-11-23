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

    static func make(
        recording: Recording?, offer: String?, meetings: [Meeting], dismissed: Set<String>, now: Date
    ) -> [PopupCard] {
        var cards: [PopupCard] = []
        if let recording {
            cards.append(.recording(label: recording.source.label, since: recording.startedAt))
        } else if let offer {
            cards.append(.offer(service: offer))
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
