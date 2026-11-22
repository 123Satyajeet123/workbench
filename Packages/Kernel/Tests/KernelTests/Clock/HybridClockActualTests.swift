import Kernel
import Testing

/// Ported from Actual `packages/crdt/src/crdt/timestamp.test.ts` (9f62569f975d), lines 29-131 and 135-326. Actual
/// mocks `Date.now`; here the wall clock is an argument. Actual's string form becomes the packed value, its node id
/// leaves the stamp, and two of its errors change on purpose: counter overflow carries into the next millisecond,
/// and a drifting clock keeps stamping (see `HybridClockTests`).
@Suite struct HybridClockActualTests {
    private func stamp(_ millis: Int64, _ counter: UInt16) throws -> HybridTimestamp {
        try #require(HybridTimestamp(millis: millis, counter: counter))
    }

    /// timestamp.test.ts 17-27.
    @Test func stampsAreInOrder() {
        var clock = HybridClock()
        let sent = clock.send(wallMillis: 0)
        #expect(HybridTimestamp.zero < HybridTimestamp.max)
        #expect(sent > .zero)
        #expect(sent < .max)
    }

    /// timestamp.test.ts 29-50: out-of-range parts are refused.
    @Test func outOfRangePartsAreRefused() {
        #expect(HybridTimestamp(millis: -1, counter: 0) == nil)
        #expect(HybridTimestamp(millis: HybridTimestamp.maximumMillis + 1, counter: 0) == nil)
        #expect(HybridTimestamp(millis: 253_402_300_799_999, counter: 0xFFFF) == nil)
        #expect(HybridTimestamp(rawValue: -1) == nil)
    }

    /// timestamp.test.ts 52-69: valid parts round-trip. Actual ends at 9999-12-31; this range ends at 2^47 - 1 ms (year
    /// 6429), so its last vector becomes the last stamp of this range.
    @Test func validPartsRoundTrip() throws {
        for (millis, counter) in [
            (Int64(0), UInt16(0)), (1_429_914_222_123, 0x1000), (HybridTimestamp.maximumMillis, 0xFFFF),
        ] {
            let packed = try stamp(millis, counter)
            #expect(packed.millis == millis)
            #expect(packed.counter == counter)
            #expect(HybridTimestamp(rawValue: packed.rawValue) == packed)
        }
    }

    /// timestamp.test.ts 72-86.
    @Test func sendsRiseWithARisingClock() throws {
        var clock = HybridClock()
        #expect(clock.send(wallMillis: 10) == (try stamp(10, 0)))
        #expect(clock.send(wallMillis: 11) == (try stamp(11, 0)))
        #expect(clock.send(wallMillis: 12) == (try stamp(12, 0)))
    }

    /// timestamp.test.ts 87-103.
    @Test func sendsRiseWithAStutteringClock() throws {
        var clock = HybridClock()
        #expect(clock.send(wallMillis: 20) == (try stamp(20, 0)))
        #expect(clock.send(wallMillis: 20) == (try stamp(20, 1)))
        #expect(clock.send(wallMillis: 20) == (try stamp(20, 2)))
        #expect(clock.send(wallMillis: 21) == (try stamp(21, 0)))
    }

    /// timestamp.test.ts 104-120.
    @Test func sendsRiseWithARegressingClock() throws {
        var clock = HybridClock()
        #expect(clock.send(wallMillis: 30) == (try stamp(30, 0)))
        #expect(clock.send(wallMillis: 29) == (try stamp(30, 1)))
        #expect(clock.send(wallMillis: 29) == (try stamp(30, 2)))
        #expect(clock.send(wallMillis: 31) == (try stamp(31, 0)))
    }

    /// timestamp.test.ts 135-160.
    @Test func receivesRiseWithAGlobalRisingClock() throws {
        var clock = HybridClock()
        #expect(clock.receive(try stamp(51, 0), wallMillis: 52) == .merged(try stamp(52, 0)))
        #expect(clock.receive(try stamp(53, 0), wallMillis: 54) == .merged(try stamp(54, 0)))
        #expect(clock.receive(try stamp(55, 0), wallMillis: 56) == .merged(try stamp(56, 0)))
    }

    /// timestamp.test.ts 162-195.
    @Test func receivesRiseWithAGlobalStutteringClock() throws {
        var clock = HybridClock()
        #expect(clock.receive(try stamp(62, 0), wallMillis: 61) == .merged(try stamp(62, 1)))
        #expect(clock.receive(try stamp(62, 1), wallMillis: 62) == .merged(try stamp(62, 2)))
        #expect(clock.receive(try stamp(62, 2), wallMillis: 62) == .merged(try stamp(62, 3)))
        #expect(clock.receive(try stamp(62, 4), wallMillis: 63) == .merged(try stamp(63, 0)))
    }

    /// timestamp.test.ts 197-221.
    @Test func receivesRiseWithALocalStutteringClock() throws {
        var clock = HybridClock()
        #expect(clock.receive(try stamp(71, 0), wallMillis: 73) == .merged(try stamp(73, 0)))
        #expect(clock.receive(try stamp(72, 0), wallMillis: 73) == .merged(try stamp(73, 1)))
        #expect(clock.receive(try stamp(73, 0), wallMillis: 74) == .merged(try stamp(74, 0)))
    }

    /// timestamp.test.ts 223-255.
    @Test func receivesRiseWithARemoteStutteringClock() throws {
        var clock = HybridClock()
        #expect(clock.receive(try stamp(83, 0), wallMillis: 81) == .merged(try stamp(83, 1)))
        #expect(clock.receive(try stamp(83, 1), wallMillis: 82) == .merged(try stamp(83, 2)))
        #expect(clock.receive(try stamp(83, 2), wallMillis: 83) == .merged(try stamp(83, 3)))
        #expect(clock.receive(try stamp(83, 3), wallMillis: 84) == .merged(try stamp(84, 0)))
    }

    /// timestamp.test.ts 256-283.
    @Test func receivesRiseWithALocalRegressingClock() throws {
        var clock = HybridClock()
        #expect(clock.receive(try stamp(91, 0), wallMillis: 93) == .merged(try stamp(93, 0)))
        #expect(clock.receive(try stamp(92, 0), wallMillis: 92) == .merged(try stamp(93, 1)))
        #expect(clock.receive(try stamp(93, 0), wallMillis: 91) == .merged(try stamp(93, 2)))
    }

    /// timestamp.test.ts 284-317.
    @Test func receivesRiseWithARemoteRegressingClock() throws {
        var clock = HybridClock()
        #expect(clock.receive(try stamp(103, 0), wallMillis: 101) == .merged(try stamp(103, 1)))
        #expect(clock.receive(try stamp(102, 0), wallMillis: 102) == .merged(try stamp(103, 2)))
        #expect(clock.receive(try stamp(101, 0), wallMillis: 103) == .merged(try stamp(103, 3)))
    }

    /// timestamp.test.ts 319-326: Actual throws; here the remote stamp is quarantined and the clock does not move.
    @Test func aRemoteStampFarAheadIsQuarantined() throws {
        var clock = HybridClock()
        let year1980: Int64 = 315_532_800_101
        let reception = clock.receive(try stamp(year1980, 0), wallMillis: 0)
        #expect(reception == .quarantined(untilWallMillis: year1980 - HybridClock.maximumDrift))
        #expect(clock.last == .zero)
    }
}
