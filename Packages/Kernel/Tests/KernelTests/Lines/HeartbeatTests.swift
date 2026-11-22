import Lines
import Testing

/// Each heartbeat law runs twice: it must hold on `Lines`, and it must fail on its planted break.
@Suite struct HeartbeatLawTests {
    @Test func spansDependOnlyOnTheEventSet() async { await HeartbeatLaws.spansDependOnlyOnTheEventSet(.lines) }

    @Test(.shrinking(false)) func spansDependOnlyOnTheEventSetCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("events merged in the order given, into the last span only") {
            await HeartbeatLaws.spansDependOnlyOnTheEventSet(.givenOrder)
        }
    }

    @Test func aChainBreakAlwaysSeparates() async { await HeartbeatLaws.aChainBreakAlwaysSeparates(.lines) }

    @Test(.shrinking(false)) func aChainBreakCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("chain breaks are ignored") {
            await HeartbeatLaws.aChainBreakAlwaysSeparates(.ignoresBreaks)
        }
    }

    @Test func sightingsWithinThePulseShareASpan() async {
        await HeartbeatLaws.sightingsWithinThePulseShareASpan(.lines)
    }

    @Test(.shrinking(false)) func sightingsWithinThePulseCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the gap is measured from the start of the span") {
            await HeartbeatLaws.sightingsWithinThePulseShareASpan(.gapFromSpanStart)
        }
    }

    @Test func aLateSightingNeverShortensASpan() async { await HeartbeatLaws.aLateSightingNeverShortensASpan(.lines) }

    @Test(.shrinking(false)) func aLateSightingCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("a late sighting sets the end of the span") {
            await HeartbeatLaws.aLateSightingNeverShortensASpan(.lateSightingShortens)
        }
    }
}

/// Cases ported from ActivityWatch: `aw-core/tests/test_heartbeat.py:7-83` (merge rule, re-derived for sightings
/// that are instants), `aw_transform/heartbeats.py:38-40` (inclusive bound), `aw-watcher-window/main.py:31-40`
/// (pulsetime) and `:421-440` (pulsetime 0 after an excluded window).
@Suite struct HeartbeatPortedTests {
    static func mergesWithinThePulse(_ model: HeartbeatModel) {
        #expect(model.spans([], .seconds(1)).isEmpty)
        #expect(model.spans([.seen(at(seconds: 0)), .seen(at(seconds: 1))], .seconds(2)).count == 1)
    }

    @Test func mergesWithinThePulse() { Self.mergesWithinThePulse(.lines) }

    @Test func mergesWithinThePulseCatchesPlantedBreak() {
        withKnownIssue("planted break: every sighting opens a span") { Self.mergesWithinThePulse(.neverMerges) }
    }

    static func splitsOutsideThePulse(_ model: HeartbeatModel) {
        #expect(
            model.spans([.seen(at(seconds: 0)), .seen(at(seconds: 3))], .seconds(2))
                == [Span(start: at(seconds: 0), end: at(seconds: 0)), Span(start: at(seconds: 3), end: at(seconds: 3))])
    }

    @Test func splitsOutsideThePulse() { Self.splitsOutsideThePulse(.lines) }

    @Test func splitsOutsideThePulseCatchesPlantedBreak() {
        withKnownIssue("planted break: the pulse is ignored") { Self.splitsOutsideThePulse(.alwaysMerges) }
    }

    static func sameInstantInEitherOrder(_ model: HeartbeatModel) {
        let one = [Span(start: at(seconds: 0), end: at(seconds: 1))]
        #expect(model.spans([.seen(at(seconds: 0)), .seen(at(seconds: 1)), .seen(at(seconds: 0))], .seconds(5)) == one)
        #expect(model.spans([.seen(at(seconds: 1)), .seen(at(seconds: 0))], .seconds(5)) == one)
    }

    @Test func sameInstantInEitherOrder() { Self.sameInstantInEitherOrder(.lines) }

    @Test func sameInstantInEitherOrderCatchesPlantedBreak() {
        withKnownIssue("planted break: events in the order given") { Self.sameInstantInEitherOrder(.givenOrder) }
    }

    static func theBoundIsInclusive(_ model: HeartbeatModel) {
        #expect(model.spans([.seen(at(seconds: 0)), .seen(at(seconds: 2))], .seconds(2)).count == 1)
    }

    @Test func theBoundIsInclusive() { Self.theBoundIsInclusive(.lines) }

    @Test func theBoundIsInclusiveCatchesPlantedBreak() {
        withKnownIssue("planted break: a strict bound") { Self.theBoundIsInclusive(.strictBoundary) }
    }

    static func anExclusionBreaksTheChain(_ model: HeartbeatModel) {
        let events: [HeartbeatEvent] = [.seen(at(seconds: 0)), .chainBreak(at(seconds: 1)), .seen(at(seconds: 2))]
        #expect(model.spans(events, .seconds(45)).count == 2)
    }

    @Test func anExclusionBreaksTheChain() { Self.anExclusionBreaksTheChain(.lines) }

    @Test func anExclusionBreaksTheChainCatchesPlantedBreak() {
        withKnownIssue("planted break: chain breaks are ignored") { Self.anExclusionBreaksTheChain(.ignoresBreaks) }
    }

    /// `max(poll * 1.5, poll + 1)`: the extra second covers scheduler jitter at short polls.
    static func thePulseScalesWithTheFallbackInterval(_ model: HeartbeatModel) {
        #expect(model.pulse(.milliseconds(500)) == .milliseconds(1500))
        #expect(model.pulse(.seconds(1)) == .seconds(2))
        #expect(model.pulse(.seconds(5)) == .milliseconds(7500))
        #expect(model.pulse(.seconds(30)) == .seconds(45))
    }

    @Test func thePulseScalesWithTheFallbackInterval() { Self.thePulseScalesWithTheFallbackInterval(.lines) }

    @Test func thePulseCatchesPlantedBreak() {
        withKnownIssue("planted break: one and a half intervals, no extra second") {
            Self.thePulseScalesWithTheFallbackInterval(.pulseOneAndAHalfOnly)
        }
    }

    /// The chain reports what each sighting did, so a writer knows whether to extend a row or open a span.
    @Test func theChainReportsEachSighting() {
        var chain = HeartbeatChain(pulse: .seconds(10))
        #expect(chain.see(at(seconds: 5)) == .opened(closing: nil))
        #expect(chain.see(at(seconds: 12)) == .extended)
        #expect(chain.see(at(seconds: 12)) == .covered)
        #expect(chain.see(at(seconds: 8)) == .covered)
        #expect(chain.see(at(seconds: 1)) == .outOfOrder)
        #expect(chain.see(at(seconds: 30)) == .opened(closing: Span(start: at(seconds: 5), end: at(seconds: 12))))
        #expect(chain.breakChain() == Span(start: at(seconds: 30), end: at(seconds: 30)))
        #expect(chain.see(at(seconds: 31)) == .opened(closing: nil))
    }

    /// A pulse keeps its fraction of a second: with a 5 s fallback the pulse is 7.5 s, so a gap of 7.2 s extends the
    /// span and a gap of 7.6 s opens a new one.
    @Test func aPulseKeepsItsFractionOfASecond() {
        let pulse = Heartbeat.pulse(fallbackInterval: .seconds(5))
        let start = at(seconds: 0).milliseconds
        var chain = HeartbeatChain(pulse: pulse)
        #expect(chain.see(UTCInstant(milliseconds: start)) == .opened(closing: nil))
        #expect(chain.see(UTCInstant(milliseconds: start + 7_200)) == .extended)
        #expect(chain.see(UTCInstant(milliseconds: start + 14_800)) != .extended)
        let events: [HeartbeatEvent] = [0, 7_200, 14_800].map { .seen(UTCInstant(milliseconds: start + $0)) }
        #expect(Heartbeat.spans(events, pulse: pulse).count == 2)
    }
}
