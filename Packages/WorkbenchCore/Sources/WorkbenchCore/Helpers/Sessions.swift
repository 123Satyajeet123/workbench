import Foundation

/// A stretch of time on one window: one app, one title, one address.
public struct ScreenSession: Sendable, Equatable {
    /// The number the model cites, from 1.
    public var number: Int
    public var start: Date
    public var end: Date
    public var app: String
    public var title: String
    public var document: String?

    public var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

/// Turns the activity log into sessions. Code only joins time: what a session means is the model's call.
public enum Sessions {
    /// A gap up to this long between two sessions on the same window joins them.
    public static let joinGap: TimeInterval = 120
    /// Shorter sessions are passes through a window on the way to another, and are left out.
    public static let shortest: TimeInterval = 10

    /// The sessions inside `start..<end`. A window row opens a session; idle, sleep, a hidden window or the next window
    /// closes it; back from idle reopens the same window. Text and file rows do not change the window.
    public static func make(from activities: [Activity], start: Date, end: Date) -> [ScreenSession] {
        var closed: [ScreenSession] = []
        var place: Activity?
        var opened: Date?
        func close(at time: Date) {
            if let place, let opened, time > opened {
                closed.append(
                    ScreenSession(
                        number: 0, start: opened, end: time, app: place.app, title: place.title,
                        document: place.document))
            }
            opened = nil
        }
        for activity in activities.sorted(by: { $0.at < $1.at }) where activity.at < end {
            switch activity.kind {
            case .window:
                close(at: activity.at)
                place = activity
                opened = activity.at
            case .idle, .sleep:
                close(at: activity.at)
            case .skipped, .wake:
                close(at: activity.at)
                place = nil
            case .active:
                if opened == nil, place != nil { opened = activity.at }
            case .text, .file:
                break
            }
        }
        close(at: end)
        let clipped = closed.compactMap { session -> ScreenSession? in
            var session = session
            session.start = max(session.start, start)
            return session.end > session.start ? session : nil
        }
        return numbered(joined(joined(clipped).filter { $0.end.timeIntervalSince($0.start) >= shortest }))
    }

    private static func joined(_ sessions: [ScreenSession]) -> [ScreenSession] {
        sessions.reduce(into: []) { result, session in
            if let last = result.last, last.app == session.app, last.title == session.title,
                last.document == session.document, session.start.timeIntervalSince(last.end) <= joinGap
            {
                result[result.count - 1].end = session.end
            } else {
                result.append(session)
            }
        }
    }

    private static func numbered(_ sessions: [ScreenSession]) -> [ScreenSession] {
        sessions.enumerated().map { offset, session in
            var session = session
            session.number = offset + 1
            return session
        }
    }
}
