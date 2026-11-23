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

    public init(
        id: String, calendar: String, title: String, start: Date, end: Date, attendees: [Attendee] = [],
        notesLength: Int = 0
    ) {
        self.id = id
        self.calendar = calendar
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
        self.notesLength = notesLength
    }

    public var guests: [Attendee] { attendees.filter { !$0.isMe } }
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
