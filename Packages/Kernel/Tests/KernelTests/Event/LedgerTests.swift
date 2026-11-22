import Kernel
import Testing

@Suite struct LedgerTests {
    private let founder = EventFixture.founderMac
    private let group = EventFixture.groupLabel
    private var stream: StreamID { StreamID(device: founder.publicKey.id, label: group) }

    private func signed(sequence: UInt64, millis: Int64, backlink: Digest, body: String = "body") throws -> Event {
        let header = try EventFixture.header(
            founder, group, sequence: sequence, millis: millis, backlink: backlink, body: body)
        return try Event(signing: header, with: founder)
    }

    @Test func aChainIsAcceptedInSequenceOrder() throws {
        let chain = try EventFixture.chain(founder, group, count: 4)
        let view = EventFixture.ledger(chain.reversed()).view
        #expect(view.accepted[stream]?.map(\.id) == chain.map(\.id))
        #expect(view.forks.isEmpty && view.rejected.isEmpty && view.waiting.isEmpty)
    }

    @Test func aWrongBacklinkIsRefusedAndWhatFollowsWaits() throws {
        let chain = try EventFixture.chain(founder, group, count: 1)
        let wrong = try signed(
            sequence: 2, millis: EventFixture.startMillis + 2, backlink: EventFixture.commitment("x"))
        let next = try signed(sequence: 3, millis: EventFixture.startMillis + 3, backlink: wrong.id)
        let view = EventFixture.ledger(chain + [wrong, next]).view
        #expect(view.accepted[stream]?.map(\.id) == [chain[0].id])
        #expect(view.rejected == [wrong.id: .backlinkMismatch])
        #expect(view.waiting == [next.id])
        let right = try signed(sequence: 2, millis: EventFixture.startMillis + 2, backlink: chain[0].id)
        #expect(EventFixture.ledger(chain + [right]).view.accepted[stream]?.map(\.id) == [chain[0].id, right.id])
    }

    @Test func aStampThatDoesNotRiseIsRefused() throws {
        let first = try signed(sequence: 1, millis: EventFixture.startMillis, backlink: .zero)
        let same = try signed(sequence: 2, millis: EventFixture.startMillis, backlink: first.id)
        #expect(EventFixture.ledger([first, same]).view.rejected == [same.id: .hlcNotRising])
        let later = try signed(sequence: 2, millis: EventFixture.startMillis + 1, backlink: first.id)
        #expect(EventFixture.ledger([first, later]).view.accepted[stream]?.map(\.id) == [first.id, later.id])
    }

    @Test func aGapWaitsUntilTheMissingEventArrives() throws {
        let chain = try EventFixture.chain(founder, group, count: 3)
        let gapped = EventFixture.ledger([chain[0], chain[2]]).view
        #expect(gapped.accepted[stream]?.map(\.id) == [chain[0].id])
        #expect(gapped.waiting == [chain[2].id])
        #expect(EventFixture.ledger(chain).view.accepted[stream]?.map(\.id) == chain.map(\.id))
    }

    @Test func aSecondEventAtOnePositionIsKeptAsForkEvidence() throws {
        let chain = try EventFixture.chain(founder, group, count: 3)
        let twin = try signed(sequence: 2, millis: EventFixture.startMillis + 2, backlink: chain[0].id, body: "other")
        let view = EventFixture.ledger(chain + [twin]).view
        #expect(view.accepted[stream]?.map(\.id) == [chain[0].id])
        #expect(
            view.forks == [
                Fork(
                    position: StreamPosition(stream: stream, sequence: 2),
                    events: [chain[1], twin].sorted { $0.id < $1.id })
            ])
        #expect(view.waiting == [chain[2].id])
    }

    @Test func aTwinWithAWrongBacklinkIsStillAFork() throws {
        let chain = try EventFixture.chain(founder, group, count: 2)
        let twin = try signed(sequence: 2, millis: EventFixture.startMillis + 2, backlink: EventFixture.commitment("x"))
        let view = EventFixture.ledger(chain + [twin]).view
        #expect(view.forks.map(\.position.sequence) == [2])
        #expect(view.rejected.isEmpty)
    }

    @Test func theSameEventTwiceIsOneEvent() throws {
        let chain = try EventFixture.chain(founder, group, count: 2)
        let resigned = try Event(signing: chain[1].header, with: founder)
        let view = EventFixture.ledger(chain + [chain[1], resigned]).view
        #expect(view.accepted[stream]?.map(\.id) == chain.map(\.id))
        #expect(view.forks.isEmpty)
    }

    @Test func eachLabelHasItsOwnSequenceSoNoFalseGaps() throws {
        let inGroup = try EventFixture.chain(founder, group, count: 2)
        let inDeal = try EventFixture.chain(founder, EventFixture.dealLabel, count: 3)
        let view = EventFixture.ledger(inGroup + inDeal).view
        #expect(view.accepted.values.map(\.count).sorted() == [2, 3])
        #expect(view.waiting.isEmpty)
    }

    @Test func aForgedEventLeavesNoForkEvidence() throws {
        let chain = try EventFixture.chain(founder, group, count: 2)
        let twin = try EventFixture.header(
            founder, group, sequence: 2, millis: EventFixture.startMillis + 2, backlink: chain[0].id, body: "forged")
        var ledger = EventFixture.ledger(chain)
        #expect(throws: EventError.badSignature) {
            try ledger.insert(Event(header: twin, signature: chain[1].signature))
        }
        #expect(ledger.view.forks.isEmpty)
    }

    /// Review 1 F2: a device that withholds sequence 2 and signs two events at 3 is caught as soon as both arrive.
    @Test func aForkBehindAGapIsReported() throws {
        let chain = try EventFixture.chain(founder, group, count: 3)
        let twin = try signed(sequence: 3, millis: EventFixture.startMillis + 3, backlink: chain[1].id, body: "other")
        let view = EventFixture.ledger([chain[0], chain[2], twin]).view
        #expect(view.forks.map(\.position.sequence) == [3])
        #expect(view.accepted[stream]?.map(\.id) == [chain[0].id])
        #expect(view.waiting == [chain[2].id, twin.id])
    }

    @Test func everyForkInAStreamIsReportedNotOnlyTheFirst() throws {
        let chain = try EventFixture.chain(founder, group, count: 4)
        let twin2 = try signed(sequence: 2, millis: EventFixture.startMillis + 2, backlink: chain[0].id, body: "b2")
        let twin4 = try signed(sequence: 4, millis: EventFixture.startMillis + 4, backlink: chain[2].id, body: "b4")
        #expect(EventFixture.ledger(chain + [twin2, twin4]).view.forks.map(\.position.sequence) == [2, 4])
    }

    @Test func aTwinAtAnAcceptedPositionStopsTheChainThere() throws {
        let chain = try EventFixture.chain(founder, group, count: 4)
        let twin = try signed(sequence: 2, millis: EventFixture.startMillis + 2, backlink: chain[0].id, body: "late")
        var ledger = EventFixture.ledger(chain)
        try ledger.insert(twin)
        #expect(ledger.view.accepted[stream]?.map(\.id) == [chain[0].id])
        #expect(ledger.view.waiting == [chain[2].id, chain[3].id])
        #expect(ledger.view == EventFixture.ledger([twin] + chain.reversed()).view)
    }

    @Test func aTwinOfARefusedEventTurnsTheRefusalIntoAFork() throws {
        let first = try signed(sequence: 1, millis: EventFixture.startMillis, backlink: .zero)
        let refused = try signed(sequence: 2, millis: EventFixture.startMillis, backlink: first.id)
        let twin = try signed(sequence: 2, millis: EventFixture.startMillis + 1, backlink: first.id)
        let view = EventFixture.ledger([first, refused, twin]).view
        #expect(view.rejected.isEmpty)
        #expect(view.forks.map(\.position.sequence) == [2])
    }

    @Test func theHeadIsTheLastAcceptedEvent() throws {
        let chain = try EventFixture.chain(founder, group, count: 3)
        var ledger = Ledger(keys: EventFixture.keys)
        #expect(ledger.head(of: stream) == nil)
        try ledger.insert(chain[0])
        try ledger.insert(chain[2])
        #expect(ledger.head(of: stream)?.sequence == 1)
        #expect(ledger.head(of: stream)?.id == chain[0].id)
        try ledger.insert(chain[1])
        #expect(ledger.head(of: stream)?.sequence == 3)
        #expect(ledger.head(of: stream)?.id == chain[2].id)
    }
}

@Suite struct EventOrderTests {
    private func order(millis: Int64, device: DeviceSigningKey, sequence: UInt64) throws -> EventOrder {
        let header = try EventFixture.header(
            device, EventFixture.groupLabel, sequence: sequence, millis: millis,
            backlink: sequence == 1 ? .zero : EventFixture.commitment("x"))
        return EventOrder(header)
    }

    @Test func stampsDecideFirst() throws {
        let founder = EventFixture.founderMac
        #expect(try order(millis: 1, device: founder, sequence: 10) < order(millis: 2, device: founder, sequence: 9))
    }

    /// `Received.swift:50` sorted `"x.10"` before `"x.9"`.
    @Test func tiesGoToTheNumericSequenceNotItsDigits() throws {
        let founder = EventFixture.founderMac
        #expect(try order(millis: 1, device: founder, sequence: 9) < order(millis: 1, device: founder, sequence: 10))
    }

    @Test func thenTheDeviceBytesDecide() throws {
        let devices = [EventFixture.founderMac, EventFixture.adityaMac].sorted { $0.publicKey.id < $1.publicKey.id }
        #expect(
            try order(millis: 1, device: devices[0], sequence: 50) < order(millis: 1, device: devices[1], sequence: 1))
    }

    /// Review 1 F12: fork twins share stamp, device, sequence and label; the id still orders them.
    @Test func forkTwinsNeverTie() throws {
        let key = EventFixture.founderMac
        let one = try EventFixture.header(
            key, EventFixture.groupLabel, sequence: 1, millis: 1, backlink: .zero, body: "a")
        let two = try EventFixture.header(
            key, EventFixture.groupLabel, sequence: 1, millis: 1, backlink: .zero, body: "b")
        #expect(EventOrder(one) != EventOrder(two))
        #expect((EventOrder(one) < EventOrder(two)) != (EventOrder(two) < EventOrder(one)))
        #expect(EventOrder(one) == EventOrder(one))
    }
}

/// Research K7 §2.4, review 1 F7: the clock's quarantine applies to events before the ledger sees them.
@Suite struct AdmissionTests {
    private func event(millis: Int64) throws -> Event {
        let header = try EventFixture.header(
            EventFixture.founderMac, EventFixture.groupLabel, sequence: 1, millis: millis, backlink: .zero)
        return try Event(signing: header, with: EventFixture.founderMac)
    }

    @Test func anEventWithinTheDriftLimitIsAdmittedAndMergesItsStamp() throws {
        var clock = HybridClock()
        let wall = EventFixture.startMillis
        let near = try event(millis: wall + HybridClock.maximumDrift)
        #expect(clock.admit(near, wallMillis: wall) == .admitted(near))
        #expect(clock.last > near.header.hlc)
    }

    @Test func anEventTooFarAheadIsQuarantinedUntilTheWallClockCatchesUp() throws {
        var clock = HybridClock()
        let wall = EventFixture.startMillis
        let far = try event(millis: wall + HybridClock.maximumDrift + 1)
        #expect(clock.admit(far, wallMillis: wall) == .quarantined(far, untilWallMillis: wall + 1))
        #expect(clock.last == .zero)
        #expect(clock.admit(far, wallMillis: wall + 1) == .admitted(far))
    }
}
