import Foundation
import WorkbenchCore

public protocol CalendarEvents: Sendable {
    func requestAccess() async -> SystemAccess
    func calendars() -> [CalendarInfo]
    func meetings(during interval: DateInterval, in calendarIDs: [String]) -> [Meeting]
}

public enum CalendarError: Error, Equatable {
    case accessRefused(SystemAccess)
}

public struct CalendarDay: Sendable, Equatable {
    public var calendars: [CalendarInfo]
    public var meetings: [Meeting]

    public static let empty = CalendarDay(calendars: [], meetings: [])

    public init(calendars: [CalendarInfo], meetings: [Meeting]) {
        self.calendars = calendars
        self.meetings = meetings
    }
}

public struct MeetingReader: Sendable {
    let calendar: any CalendarEvents
    let policy: any CapturePolicyProvider

    public init(calendar: any CalendarEvents, policy: any CapturePolicyProvider) {
        self.calendar = calendar
        self.policy = policy
    }

    public func today(at now: Date, in zone: Calendar = .current) async throws -> CalendarDay {
        let start = zone.startOfDay(for: now)
        let day = DateInterval(start: start, end: zone.date(byAdding: .day, value: 1, to: start) ?? start)
        let (calendars, meetings) = try await read(day, at: now)
        return CalendarDay(calendars: calendars, meetings: meetings)
    }

    public func meetings(during interval: DateInterval, at now: Date) async throws -> [Meeting] {
        try await read(interval, at: now).meetings
    }

    private func read(_ interval: DateInterval, at now: Date) async throws -> (
        calendars: [CalendarInfo], meetings: [Meeting]
    ) {
        let current = try await policy.currentPolicy()
        guard current.isEnabled(.calendar) else { throw ReadError.denied(.sourceSwitchedOff) }
        let access = await calendar.requestAccess()
        guard access == .allowed else { throw CalendarError.accessRefused(access) }
        let calendars = calendar.calendars()
        var chosen: [String] = []
        for each in calendars {
            switch current.authorize(CaptureRequest(kind: .calendar, label: each.id), at: now) {
            case .allow: chosen.append(each.id)
            case .deny(.labelNotAllowed), .deny(.labelDenied): continue
            case .deny(let reason): throw ReadError.denied(reason)
            case .confirm: throw ReadError.denied(.privateMode)
            }
        }
        let meetings = chosen.isEmpty ? [] : calendar.meetings(during: interval, in: chosen)
        return (calendars, meetings.sorted { $0.start < $1.start })
    }
}
