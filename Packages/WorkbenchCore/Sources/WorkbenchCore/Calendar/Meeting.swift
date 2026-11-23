import Foundation

/// One calendar event of the day, with only what Today needs. The notes are never kept, only their length.
public struct Meeting: Sendable, Equatable, Identifiable {
    public struct Attendee: Sendable, Equatable {
        public var name: String
        public var email: String
        public var isMe: Bool

        public init(name: String, email: String, isMe: Bool = false) {
            self.name = name
            self.email = email
            self.isMe = isMe
        }
    }

    public var id: String
    public var calendar: String
    public var title: String
    public var start: Date
    public var end: Date
    public var attendees: [Attendee]
    public var notesLength: Int
    public var joinURL: URL?
    public var isAllDay: Bool

    public init(
        id: String, calendar: String, title: String, start: Date, end: Date, attendees: [Attendee] = [],
        notesLength: Int = 0, joinURL: URL? = nil, isAllDay: Bool = false
    ) {
        self.id = id
        self.calendar = calendar
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
        self.notesLength = notesLength
        self.joinURL = joinURL
        self.isAllDay = isAllDay
    }

    public var joinService: String? { joinURL.flatMap(MeetingLink.service(of:)) }

    public var guests: [Attendee] { attendees.filter { !$0.isMe } }

    public static func during(_ start: Date, _ end: Date, in meetings: [Meeting]) -> Meeting? {
        let call = DateInterval(start: start, end: max(start, end))
        let overlaps = meetings.compactMap { meeting -> (meeting: Meeting, seconds: TimeInterval)? in
            guard !meeting.isAllDay, meeting.end > meeting.start,
                let shared = call.intersection(with: DateInterval(start: meeting.start, end: meeting.end)),
                shared.duration > 0 || call.duration == 0
            else { return nil }
            return (meeting, shared.duration)
        }
        return overlaps.max { a, b in
            (a.seconds, -abs(a.meeting.start.timeIntervalSince(start)))
                < (b.seconds, -abs(b.meeting.start.timeIntervalSince(start)))
        }?.meeting
    }
}

public struct CalendarInfo: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// False for a calendar of birthdays or a subscribed feed, such as public holidays.
    public var isMeetingCalendar: Bool

    public init(id: String, title: String, isMeetingCalendar: Bool = true) {
        self.id = id
        self.title = title
        self.isMeetingCalendar = isMeetingCalendar
    }
}

extension Sequence<CalendarInfo> {
    /// The calendars that Today reads: the chosen ones, or every meeting calendar until the person chooses.
    public func read(chosen: Set<String>?) -> [CalendarInfo] {
        filter { chosen?.contains($0.id) ?? $0.isMeetingCalendar }
    }
}
