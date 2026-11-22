import Lines
import PropertyBased
import Testing

/// The heartbeat functions a law checks. `lines` is the code under test; every other value is a planted break.
struct HeartbeatModel: Sendable {
    var spans: @Sendable ([HeartbeatEvent], Duration) -> [Span]
    /// The open span after `seen` (in time order) and then one late sighting.
    var afterLateSighting: @Sendable ([UTCInstant], UTCInstant, Duration) -> Span?
    var pulse: @Sendable (Duration) -> Duration

    static let lines = HeartbeatModel(
        spans: { Heartbeat.spans($0, pulse: $1) },
        afterLateSighting: { seen, late, pulse in
            var chain = HeartbeatChain(pulse: pulse)
            for instant in seen + [late] { _ = chain.see(instant) }
            return chain.open
        },
        pulse: { Heartbeat.pulse(fallbackInterval: $0) }
    )

    /// A plain fold written for the breaks: events in time order unless `sorted` is false, a chain break closes the
    /// open span unless `honoursBreaks` is false, and `joins` says whether a sighting extends the open span.
    static func fold(
        sorted: Bool = true, honoursBreaks: Bool = true,
        joins: @escaping @Sendable (Span, UTCInstant, Int64) -> Bool = { $1.milliseconds - $0.end.milliseconds <= $2 }
    ) -> HeartbeatModel {
        var model = lines
        model.spans = { events, pulse in
            let pulse = pulse.components.seconds * 1000 + pulse.components.attoseconds / 1_000_000_000_000_000
            let ordered = sorted ? events.sorted(by: inTimeOrder) : events
            var spans: [Span] = []
            var open: Span?
            for event in ordered {
                switch event {
                case .chainBreak:
                    guard honoursBreaks, let span = open else { continue }
                    spans.append(span)
                    open = nil
                case .seen(let instant):
                    if let span = open, instant >= span.start, joins(span, instant, pulse) {
                        open = Span(start: span.start, end: max(span.end, instant))
                    } else {
                        if let span = open { spans.append(span) }
                        open = Span(start: instant, end: instant)
                    }
                }
            }
            return spans + (open.map { [$0] } ?? [])
        }
        return model
    }

    static func inTimeOrder(_ a: HeartbeatEvent, _ b: HeartbeatEvent) -> Bool {
        (a.instant, a.isBreak ? 0 : 1) < (b.instant, b.isBreak ? 0 : 1)
    }

    /// Events taken in the order given, merged only into the last span (ActivityWatch `heartbeat_reduce`).
    static let givenOrder = fold(sorted: false)
    static let ignoresBreaks = fold(honoursBreaks: false)
    static let gapFromSpanStart = fold(joins: { $1.milliseconds - $0.start.milliseconds <= $2 })
    static let neverMerges = fold(joins: { _, _, _ in false })
    static let alwaysMerges = fold(joins: { _, _, _ in true })
    static let strictBoundary = fold(joins: { $1.milliseconds - $0.end.milliseconds < $2 })

    static let lateSightingShortens: HeartbeatModel = {
        var model = lines
        model.afterLateSighting = { seen, late, pulse in
            guard let open = lines.afterLateSighting(seen, late, pulse) else { return nil }
            return late >= open.start && late <= open.end ? Span(start: open.start, end: late) : open
        }
        return model
    }()

    static let pulseOneAndAHalfOnly: HeartbeatModel = {
        var model = lines
        model.pulse = { $0 * 1.5 }
        return model
    }()
}

extension HeartbeatEvent {
    var instant: UTCInstant {
        switch self {
        case .seen(let instant), .chainBreak(let instant): instant
        }
    }

    var isBreak: Bool {
        if case .chainBreak = self { return true }
        return false
    }
}

func at(seconds: Int64) -> UTCInstant { UTCInstant(milliseconds: 1_795_305_600_000 + seconds * 1000) }

enum HeartbeatWorld {
    static let pulses: [Duration] = [.seconds(5), .seconds(15), .seconds(45)]

    /// Sightings a few seconds apart with gaps and chain breaks between them, a pulse, and the same events shuffled
    /// with some repeated.
    static let events = Generator(run: { rng in
        var time: Int64 = 0
        let events = (0..<Int.random(in: 1...30, using: &rng)).map { _ -> HeartbeatEvent in
            time += Int64.random(in: 0...(Int.random(in: 0..<5, using: &rng) == 0 ? 120 : 20), using: &rng)
            return Int.random(in: 0..<6, using: &rng) == 0 ? .chainBreak(at(seconds: time)) : .seen(at(seconds: time))
        }
        let again = events.shuffled(using: &rng) + events.filter { _ in Bool.random(using: &rng) }
        return (events, again.shuffled(using: &rng), pulses.randomElement(using: &rng)!)
    })

    /// Sightings that form one span under the pulse, and a late sighting inside it.
    static let spanAndLateSighting = Generator(run: { rng in
        let pulse = pulses.randomElement(using: &rng)!
        let step = pulse.components.seconds
        var time: Int64 = 0
        let seen = (0..<Int.random(in: 2...10, using: &rng)).map { _ -> UTCInstant in
            time += Int64.random(in: 0...step, using: &rng)
            return at(seconds: time)
        }
        return (seen, at(seconds: Int64.random(in: 0...time, using: &rng)), pulse)
    })
}

enum HeartbeatLaws {
    static let cases = 300

    /// The spans are a function of the set of events: order and repeats change nothing.
    static func spansDependOnlyOnTheEventSet(_ model: HeartbeatModel) async {
        await propertyCheck(count: cases, input: HeartbeatWorld.events) { input in
            let (events, again, pulse) = input
            #expect(model.spans(again, pulse) == model.spans(events, pulse))
        }
    }

    /// No span runs across a chain break: a sighting at or after a break never joins a span from before it.
    static func aChainBreakAlwaysSeparates(_ model: HeartbeatModel) async {
        await propertyCheck(count: cases, input: HeartbeatWorld.events) { input in
            let (events, _, pulse) = input
            let spans = model.spans(events, pulse)
            for case .chainBreak(let instant) in events {
                #expect(!spans.contains { $0.start < instant && instant <= $0.end })
            }
        }
    }

    /// Spans are sorted and apart; each sighting is in one span; two sightings in a row with no break between them
    /// share a span exactly when the second comes at most one pulse after the first.
    static func sightingsWithinThePulseShareASpan(_ model: HeartbeatModel) async {
        await propertyCheck(count: cases, input: HeartbeatWorld.events) { input in
            let (events, _, pulse) = input
            let spans = model.spans(events, pulse)
            let pulseMillis = pulse.components.seconds * 1000
            #expect(zip(spans, spans.dropFirst()).allSatisfy { $0.end < $1.start })
            let ordered = events.sorted(by: HeartbeatModel.inTimeOrder)
            var previous: UTCInstant?
            for event in ordered {
                guard case .seen(let instant) = event else {
                    previous = nil
                    continue
                }
                let holders = spans.filter { $0.start <= instant && instant <= $0.end }
                #expect(holders.count == 1)
                if let previous, previous != instant {
                    let shared = holders.first.map { $0.start <= previous } ?? false
                    #expect(shared == (instant.milliseconds - previous.milliseconds <= pulseMillis))
                }
                previous = instant
            }
        }
    }

    /// A sighting that arrives late, inside the open span, never shortens it (ActivityWatch takes the maximum
    /// duration, `heartbeats.py:50-52`).
    static func aLateSightingNeverShortensASpan(_ model: HeartbeatModel) async {
        await propertyCheck(count: cases, input: HeartbeatWorld.spanAndLateSighting) { input in
            let (seen, late, pulse) = input
            #expect(model.afterLateSighting(seen, late, pulse) == model.afterLateSighting(seen, seen.last!, pulse))
        }
    }
}
