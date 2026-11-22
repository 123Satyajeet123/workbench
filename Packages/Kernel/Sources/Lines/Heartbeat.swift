// Source: ports ActivityWatch aw-core `aw_transform/heartbeats.py:26-56` (merge within the pulse, inclusive bound,
// the end never moves back) and aw-watcher-window `main.py:31-40` (pulse) and `:421-440` (no merge across an
// excluded window), re-derived for sightings that are instants and for any delivery order (ADR-014).

/// The time a line was seen without a gap: from its first sighting to its last.
public struct Span: Hashable, Sendable {
    public let start: UTCInstant
    public let end: UTCInstant

    public init(start: UTCInstant, end: UTCInstant) {
        precondition(start <= end, "a span ends before it starts")
        self.start = start
        self.end = end
    }
}

/// What a reader reports about one line: it saw the line at an instant, or the chain broke (sleep, lock, idle, an
/// excluded app or window, a consent change), so no span may run across that instant.
public enum HeartbeatEvent: Hashable, Sendable {
    case seen(UTCInstant)
    case chainBreak(UTCInstant)
}

/// What one sighting did to the open span.
public enum Sighting: Equatable, Sendable {
    /// A new span opened; `closing` is the span it ended, if one was open.
    case opened(closing: Span?)
    /// The open span now ends at this sighting.
    case extended
    /// The sighting is inside the open span, so nothing changed.
    case covered
    /// The sighting is before the open span. A live chain takes sightings in time order; use `Heartbeat.spans` to
    /// merge events that arrive in any order.
    case outOfOrder
}

/// The open span of one line, for a reader that sees the line again and again.
public struct HeartbeatChain: Sendable {
    public let pulse: Duration
    public private(set) var open: Span?

    public init(pulse: Duration) { self.pulse = pulse }

    /// A sighting at most one pulse after the open span's end extends it; a later one, or the first after a chain
    /// break, opens a new span.
    public mutating func see(_ instant: UTCInstant) -> Sighting {
        guard let span = open else {
            open = Span(start: instant, end: instant)
            return .opened(closing: nil)
        }
        if instant < span.start { return .outOfOrder }
        if instant <= span.end { return .covered }
        if instant.milliseconds - span.end.milliseconds <= pulse.milliseconds {
            open = Span(start: span.start, end: instant)
            return .extended
        }
        open = Span(start: instant, end: instant)
        return .opened(closing: span)
    }

    /// Closes the open span; the next sighting opens a new one.
    public mutating func breakChain() -> Span? {
        defer { open = nil }
        return open
    }
}

public enum Heartbeat {
    /// The longest gap between two sightings of one span, for a reader whose slowest re-read comes every
    /// `fallbackInterval`: one and a half intervals, and at least one second more than one interval.
    public static func pulse(fallbackInterval: Duration) -> Duration {
        max(fallbackInterval * 1.5, fallbackInterval + .seconds(1))
    }

    /// The spans of one line from events in any order, repeats included. Events are taken in time order; at one
    /// instant a chain break comes before a sighting, so a line seen right after a break opens a new span.
    public static func spans(_ events: [HeartbeatEvent], pulse: Duration) -> [Span] {
        var chain = HeartbeatChain(pulse: pulse)
        var spans: [Span] = []
        for event in events.sorted(by: inTimeOrder) {
            switch event {
            case .seen(let instant):
                if case .opened(let closing?) = chain.see(instant) { spans.append(closing) }
            case .chainBreak:
                if let closing = chain.breakChain() { spans.append(closing) }
            }
        }
        return spans + (chain.open.map { [$0] } ?? [])
    }

    private static func inTimeOrder(_ a: HeartbeatEvent, _ b: HeartbeatEvent) -> Bool {
        rank(a) < rank(b)
    }

    private static func rank(_ event: HeartbeatEvent) -> (Int64, Int) {
        switch event {
        case .chainBreak(let instant): (instant.milliseconds, 0)
        case .seen(let instant): (instant.milliseconds, 1)
        }
    }
}
