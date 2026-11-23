import Foundation
import WorkbenchCore

/// The Mac's calendar, behind a seam so a test can use a fake. It only reads.
public protocol CalendarEvents: Sendable {
    /// Asks macOS once when it has not asked before; otherwise reports what the person chose.
    func requestAccess() async -> CalendarAccess
    func calendars() -> [CalendarInfo]
    /// The events that start in `interval`, in the calendars with these ids.
    func meetings(during interval: DateInterval, in calendarIDs: [String]) -> [Meeting]
}

public enum CalendarAccess: Sendable, Equatable {
    case allowed
    /// The person said no, now or before; only System Settings can change it.
    case blocked
    case failed(String)
}

public enum CalendarError: Error, Equatable {
    case accessRefused(CalendarAccess)
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

/// Reads today's meetings. It asks the capture policy for each calendar before it reads that calendar, and asks macOS
/// for access only after the policy allows the kind.
public struct MeetingReader: Sendable {
    let calendar: any CalendarEvents
    let policy: any CapturePolicyProvider

    public init(calendar: any CalendarEvents, policy: any CapturePolicyProvider) {
        self.calendar = calendar
        self.policy = policy
    }

    public func today(at now: Date, in zone: Calendar = .current) async throws -> CalendarDay {
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
        let start = zone.startOfDay(for: now)
        let day = DateInterval(start: start, end: zone.date(byAdding: .day, value: 1, to: start) ?? start)
        let meetings = chosen.isEmpty ? [] : calendar.meetings(during: day, in: chosen)
        return CalendarDay(calendars: calendars, meetings: meetings.sorted { $0.start < $1.start })
    }
}
