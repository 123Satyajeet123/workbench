import EventKit
import Foundation
import WorkbenchCore

/// The real calendar, through EventKit with full read access. It never saves an event.
public final class EventKitCalendar: CalendarEvents, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async -> SystemAccess { await EventKitAccess.request(.event) }

    public func calendars() -> [CalendarInfo] {
        store.calendars(for: .event).map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
    }

    public func meetings(during interval: DateInterval, in calendarIDs: [String]) -> [Meeting] {
        let chosen = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: chosen)
        return store.events(matching: predicate).filter { $0.status != .canceled }.map(Self.meeting)
    }

    private static func meeting(_ event: EKEvent) -> Meeting {
        Meeting(
            id: event.eventIdentifier ?? UUID().uuidString, calendar: event.calendar.calendarIdentifier,
            title: event.title ?? "", start: event.startDate, end: event.endDate,
            attendees: (event.attendees ?? []).map {
                Meeting.Attendee(
                    name: $0.name ?? "", email: $0.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
                    isMe: $0.isCurrentUser)
            },
            notesLength: event.notes?.count ?? 0)
    }
}
