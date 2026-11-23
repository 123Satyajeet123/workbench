import Foundation

/// A stretch of time on one window: one app, one title, one address.
public struct ScreenSession: Sendable, Equatable {
    /// The id the model cites: the evidence line of the stretch, or, before it is stored, the activity row that opened
    /// it (a window, or back from idle).
    public var id: Int64
    public var start: Date
    public var end: Date
    public var app: String
    public var bundleID = ""
    public var title: String
    public var document: String?
    /// The stored line behind this stretch; nil before it is stored.
    public var lineID: Data?
    public var provenance: Provenance?

    public var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

/// Follows the activity log in time order and gives each stretch on one window when it closes. A window row opens a
/// stretch; idle, sleep, a hidden window or the next window closes it; back from idle reopens the same window. Text
/// and file rows do not change the window.
public struct ScreenStretches: Sendable {
    private var place: Activity?
    private var opened: Date?
    private var opener: Int64 = 0

    public init() {}

    /// The stretch this activity closes, if any. `id` is the activity's row id.
    public mutating func feed(_ activity: Activity, id: Int64) -> ScreenSession? {
        switch activity.kind {
        case .window:
            let closed = close(at: activity.at)
            place = activity
            opened = activity.at
            opener = id
            return closed
        case .idle, .sleep:
            return close(at: activity.at)
        case .skipped, .wake:
            let closed = close(at: activity.at)
            place = nil
            return closed
        case .active:
            if opened == nil, place != nil {
                opened = activity.at
                opener = id
            }
            return nil
        case .text, .page, .file:
            return nil
        }
    }

    /// The open stretch, ended at `time`, if there is one.
    public mutating func close(at time: Date) -> ScreenSession? {
        defer { opened = nil }
        guard let place, let opened, time > opened else { return nil }
        return ScreenSession(
            id: opener, start: opened, end: time, app: place.app, bundleID: place.bundleID, title: place.title,
            document: place.document)
    }
}

/// Turns the activity log into sessions. Code only joins time: what a session means is the model's call.
public enum Sessions {
    /// A gap up to this long between two sessions on the same window joins them.
    public static let joinGap: TimeInterval = 120
    /// Shorter sessions are passes through a window on the way to another, and are left out.
    public static let shortest: TimeInterval = 10

    /// The sessions inside `start..<end`.
    public static func make(from activities: [Activity], start: Date, end: Date) -> [ScreenSession] {
        var stretches = ScreenStretches()
        var closed: [ScreenSession] = []
        // Rows read from the store have ids; rows built in memory get one from their place in the list.
        for (offset, activity) in activities.sorted(by: { $0.at < $1.at }).enumerated() where activity.at < end {
            closed += stretches.feed(activity, id: activity.id ?? -Int64(offset + 1)).map { [$0] } ?? []
        }
        closed += stretches.close(at: end).map { [$0] } ?? []
        let clipped = closed.compactMap { session -> ScreenSession? in
            var session = session
            session.start = max(session.start, start)
            return session.end > session.start ? session : nil
        }
        return joined(joined(clipped).filter { $0.end.timeIntervalSince($0.start) >= shortest })
    }

    private static func joined(_ sessions: [ScreenSession]) -> [ScreenSession] {
        sessions.reduce(into: []) { result, session in
            if let last = result.last, last.isSameWindow(as: session),
                session.start.timeIntervalSince(last.end) <= joinGap
            {
                result[result.count - 1].end = session.end
            } else {
                result.append(session)
            }
        }
    }
}
