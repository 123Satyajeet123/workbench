import Foundation

public struct ScreenSession: Sendable, Equatable {
    public var id: Int64
    public var start: Date
    public var end: Date
    public var app: String
    public var title: String
    public var document: String?

    public var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

public enum Sessions {
    public static let joinGap: TimeInterval = 120
    public static let shortest: TimeInterval = 10

    public static func make(from activities: [Activity], start: Date, end: Date) -> [ScreenSession] {
        var closed: [ScreenSession] = []
        var place: Activity?
        var opened: Date?
        var opener: Int64 = 0
        func close(at time: Date) {
            if let place, let opened, time > opened {
                closed.append(
                    ScreenSession(
                        id: opener, start: opened, end: time, app: place.app, title: place.title,
                        document: place.document))
            }
            opened = nil
        }
        for (offset, activity) in activities.sorted(by: { $0.at < $1.at }).enumerated() where activity.at < end {
            let rowID = activity.id ?? -Int64(offset + 1)
            switch activity.kind {
            case .window:
                close(at: activity.at)
                place = activity
                opened = activity.at
                opener = rowID
            case .idle, .sleep:
                close(at: activity.at)
            case .skipped, .wake:
                close(at: activity.at)
                place = nil
            case .active:
                if opened == nil, place != nil {
                    opened = activity.at
                    opener = rowID
                }
            case .text, .page, .file:
                break
            }
        }
        close(at: end)
        let clipped = closed.compactMap { session -> ScreenSession? in
            var session = session
            session.start = max(session.start, start)
            return session.end > session.start ? session : nil
        }
        return joined(joined(clipped).filter { $0.end.timeIntervalSince($0.start) >= shortest })
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
}
