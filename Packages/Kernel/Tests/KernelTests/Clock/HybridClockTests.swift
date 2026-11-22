import Kernel
import PropertyBased
import Testing

@Suite struct HybridClockTests {
    private func stamp(_ millis: Int64, _ counter: UInt16) throws -> HybridTimestamp {
        try #require(HybridTimestamp(millis: millis, counter: counter))
    }

    @Test func theStampPacksFortyEightBitsOfMillisecondsAndSixteenOfCounter() throws {
        let packed = try stamp(1_795_305_600_000, 3)
        #expect(packed.rawValue == 0x01a2_008d_7400_0003)
        #expect(HybridTimestamp(rawValue: 0x01a2_008d_7400_0003) == packed)
        #expect(HybridTimestamp.max.millis == HybridTimestamp.maximumMillis)
        #expect(HybridTimestamp.max.counter == .max)
        #expect(HybridTimestamp.max.rawValue == .max)
    }

    @Test func aFullCounterCarriesIntoTheNextMillisecond() throws {
        var clock = HybridClock()
        for counter in 0...UInt16.max {
            #expect(clock.send(wallMillis: 40) == (try stamp(40, counter)))
        }
        #expect(clock.send(wallMillis: 40) == (try stamp(41, 0)))
        #expect(clock.send(wallMillis: 41) == (try stamp(41, 1)))
    }

    @Test func aRemoteStampWithAFullCounterCarriesOnReceive() throws {
        var clock = HybridClock()
        #expect(clock.receive(try stamp(100, .max), wallMillis: 50) == .merged(try stamp(101, 0)))
    }

    /// Actual timestamp.test.ts 128-131 throws here; the owner's work must not stop, so the clock keeps stamping and
    /// says that it runs ahead of the wall clock.
    @Test func aClockAheadOfTheWallKeepsStampingAndSaysSo() throws {
        var clock = HybridClock()
        let start: Int64 = 1_795_305_600_000
        #expect(clock.send(wallMillis: start) == (try stamp(start, 0)))
        let setBack = start - HybridClock.maximumDrift - 1
        #expect(clock.send(wallMillis: setBack) == (try stamp(start, 1)))
        #expect(clock.isAhead(ofWallMillis: setBack))
        #expect(!clock.isAhead(ofWallMillis: setBack + 1))
    }

    @Test func aWallClockBeforeNineteenSeventyStampsAfterTheLastStamp() throws {
        var clock = HybridClock()
        #expect(clock.send(wallMillis: .min) == (try stamp(0, 1)))
        #expect(!clock.isAhead(ofWallMillis: .min))
    }

    @Test func aRemoteStampExactlyAtTheDriftLimitMerges() throws {
        var clock = HybridClock()
        let wall: Int64 = 1_000_000
        let atLimit = try stamp(wall + HybridClock.maximumDrift, 7)
        #expect(clock.receive(atLimit, wallMillis: wall) == .merged(try stamp(wall + HybridClock.maximumDrift, 8)))
    }

    @Test func aQuarantinedStampMergesOnceTheWallClockCatchesUp() throws {
        var clock = HybridClock()
        let wall: Int64 = 1_000_000
        let ahead = try stamp(wall + HybridClock.maximumDrift + 1, 0)
        guard case .quarantined(let until) = clock.receive(ahead, wallMillis: wall) else {
            Issue.record("a stamp past the drift limit merged")
            return
        }
        #expect(until == wall + 1)
        #expect(clock.last == .zero)
        #expect(clock.receive(ahead, wallMillis: until) == .merged(try stamp(ahead.millis, 1)))
    }

    @Test func theLastStampOfTheRangeStaysTheLast() {
        var clock = HybridClock(last: .max)
        #expect(clock.send(wallMillis: .max) == .max)
        #expect(clock.receive(.max, wallMillis: .max) == .merged(.max))
    }

    @Test func aWallClockPastTheRangeStampsTheEndOfTheRange() throws {
        var clock = HybridClock()
        #expect(clock.send(wallMillis: .max) == (try stamp(HybridTimestamp.maximumMillis, 0)))
    }
}

/// Clock properties over random walls (skewed, stuttering, regressing) and random remote stamps.
@Suite struct HybridClockLawTests {
    @Test func stampsStrictlyRise() async { await ClockLaws.stampsStrictlyRise(.kernel) }

    @Test(.shrinking(false)) func stampsStrictlyRiseCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("a regressing wall clock resets the stamp (p2panda timestamp.rs:124-148)") {
            await ClockLaws.stampsStrictlyRise(.resetsOnRegressingWall)
        }
    }

    @Test func farFutureStampsNeverMoveTheClock() async { await ClockLaws.farFutureStampsNeverMoveTheClock(.kernel) }

    @Test(.shrinking(false)) func farFutureStampsCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("every remote stamp is merged") {
            await ClockLaws.farFutureStampsNeverMoveTheClock(.mergesEveryRemoteStamp)
        }
    }
}

enum ClockStep: Sendable {
    case send(wall: Int64)
    case receive(remote: HybridTimestamp, wall: Int64)
}

enum ClockLaws {
    static let base: Int64 = 1_795_305_600_000
    static let skew: Int64 = 10 * 60 * 1000

    static let wall = Gen.int64(in: (base - skew)...(base + skew))
    static let remote = zip(Gen.int64(in: (base - 2 * skew)...(base + 2 * skew)), Gen.uint16(in: 0...3))
        .compactMap { HybridTimestamp(millis: $0, counter: $1) }

    static let step = zip(Gen.bool(), wall, remote).map { isSend, wall, remote in
        isSend ? ClockStep.send(wall: wall) : .receive(remote: remote, wall: wall)
    }

    /// Every stamp the clock gives, by send or by merge, is greater than every stamp it gave before.
    static func stampsStrictlyRise(_ algebra: ClockAlgebra) async {
        await propertyCheck(count: 200, input: step.array(of: 1...40)) { steps in
            var clock = HybridClock()
            var previous: HybridTimestamp?
            for step in steps {
                guard let given = algebra.apply(step, &clock) else { continue }
                if let previous { #expect(given > previous) }
                previous = given
            }
        }
    }

    /// A remote stamp more than the drift limit ahead of the wall clock is quarantined and leaves the clock as it was;
    /// any other remote stamp merges to a stamp above it.
    static func farFutureStampsNeverMoveTheClock(_ algebra: ClockAlgebra) async {
        await propertyCheck(count: 200, input: remote, wall) { remote, wall in
            var clock = HybridClock(last: HybridTimestamp(millis: base, counter: 0) ?? .zero)
            let before = clock.last
            let reception = algebra.receive(&clock, remote, wall)
            if remote.millis - wall > HybridClock.maximumDrift {
                #expect(reception == .quarantined(untilWallMillis: remote.millis - HybridClock.maximumDrift))
                #expect(clock.last == before)
            } else {
                #expect(clock.last > remote)
                #expect(reception == .merged(clock.last))
            }
        }
    }
}

/// The clock operations a law is checked against: `kernel`, or a planted break.
struct ClockAlgebra: Sendable {
    var send: @Sendable (inout HybridClock, Int64) -> HybridTimestamp
    var receive: @Sendable (inout HybridClock, HybridTimestamp, Int64) -> HybridClock.Reception

    static let kernel = ClockAlgebra(
        send: { clock, wall in clock.send(wallMillis: wall) },
        receive: { clock, remote, wall in clock.receive(remote, wallMillis: wall) })

    static let resetsOnRegressingWall = ClockAlgebra(
        send: { clock, wall in
            let last = clock.last
            let next =
                wall == last.millis
                ? HybridTimestamp(millis: wall, counter: last.counter &+ 1) : HybridTimestamp(millis: wall, counter: 0)
            clock = HybridClock(last: next ?? last)
            return clock.last
        },
        receive: kernel.receive)

    static let mergesEveryRemoteStamp = ClockAlgebra(
        send: kernel.send,
        receive: { clock, remote, wall in
            let farWall = max(wall, remote.millis)
            return clock.receive(remote, wallMillis: farWall)
        })

    func apply(_ step: ClockStep, _ clock: inout HybridClock) -> HybridTimestamp? {
        switch step {
        case .send(let wall):
            return send(&clock, wall)
        case .receive(let remote, let wall):
            guard case .merged(let merged) = receive(&clock, remote, wall) else { return nil }
            return merged
        }
    }
}
