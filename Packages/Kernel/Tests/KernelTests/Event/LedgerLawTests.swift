import Kernel
import PropertyBased
import Testing

/// Research 47 I2: any delivery order of one event set gives one view, with the same fork evidence.
@Suite struct LedgerLawTests {
    @Test func everyDeliveryOrderGivesOneView() async { await LedgerLaws.everyDeliveryOrderGivesOneView(.kernel) }

    @Test(.shrinking(false)) func everyDeliveryOrderCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the first event seen at a position wins (p2panda ingest/operation.rs:174-190)")
        {
            await LedgerLaws.everyDeliveryOrderGivesOneView(.firstSeenWins)
        }
    }

    @Test func everyPositionWithTwoEventsIsAFork() async {
        await LedgerLaws.everyPositionWithTwoEventsIsAFork(.kernel)
    }

    @Test(.shrinking(false)) func everyPositionWithTwoEventsCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("forks are found only where the accepted chain stops") {
            await LedgerLaws.everyPositionWithTwoEventsIsAFork(.forksOnlyWhereTheChainStops)
        }
    }

    @Test func aForkBehindAWithheldEventIsSeenByMergedViews() async {
        await LedgerLaws.aForkBehindAWithheldEventIsSeenByMergedViews(.kernel)
    }

    @Test(.shrinking(false)) func aForkBehindAWithheldEventCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("forks are found only where the accepted chain stops") {
            await LedgerLaws.aForkBehindAWithheldEventIsSeenByMergedViews(.forksOnlyWhereTheChainStops)
        }
    }
}

enum LedgerLaws {
    /// Two devices, two labels, chains of one to five events, then damage: forks, wrong backlinks, stamps that do not
    /// rise, dropped events and re-signed copies. Returns the set in two independent random orders.
    static let deliveries = Generator(run: { rng in
        let events = scenario(&rng)
        return (events.shuffled(using: &rng), events.shuffled(using: &rng))
    })

    static func scenario(_ rng: inout any SeededRandomNumberGenerator) -> [Event] {
        let streams = [EventFixture.founderMac, EventFixture.adityaMac].flatMap { key in
            [EventFixture.groupLabel, EventFixture.dealLabel].map { (key, $0) }
        }
        return streams.flatMap { key, label in damagedChain(key, label, &rng) }
    }

    private static func damagedChain(
        _ key: DeviceSigningKey, _ label: LabelID, _ rng: inout any SeededRandomNumberGenerator
    ) -> [Event] {
        let count = Int.random(in: 1...5, using: &rng)
        guard let chain = try? EventFixture.chain(key, label, count: count) else { return [] }
        var events = chain.filter { _ in Int.random(in: 0..<6, using: &rng) > 0 }
        for event in chain {
            let damage = (0..<4).map { _ in Int.random(in: 0..<6, using: &rng) == 0 }
            if damage[0] { events += variant(of: event, key, body: "twin") }
            if damage[1] { events += variant(of: event, key, backlink: EventFixture.commitment("wrong")) }
            if damage[2] { events += variant(of: event, key, millis: EventFixture.startMillis) }
            if damage[3] { events += (try? Event(signing: event.header, with: key)).map { [$0] } ?? [] }
        }
        return events
    }

    private static func variant(
        of event: Event, _ key: DeviceSigningKey, body: String = "body", backlink: Digest? = nil, millis: Int64? = nil
    ) -> [Event] {
        let header = event.header
        guard
            let changed = try? EventFixture.header(
                key, header.stream.label, sequence: header.sequence, millis: millis ?? header.hlc.millis,
                backlink: header.sequence == 1 ? .zero : backlink ?? header.backlink, body: body),
            changed != header, let signed = try? Event(signing: changed, with: key)
        else { return [] }
        return [signed]
    }

    static func everyDeliveryOrderGivesOneView(_ algebra: LedgerAlgebra) async {
        await propertyCheck(count: 150, input: deliveries) { first, second in
            #expect(algebra.view(first) == algebra.view(second))
        }
    }

    /// Review 1 F2: every position that holds two correctly signed events is reported, wherever it is in its stream.
    static func everyPositionWithTwoEventsIsAFork(_ algebra: LedgerAlgebra) async {
        await propertyCheck(count: 150, input: deliveries) { events, _ in
            let ids = Dictionary(grouping: events, by: \.header.position).mapValues { Set($0.map(\.id)) }
            let twins = Set(ids.filter { $0.value.count > 1 }.keys)
            #expect(Set(algebra.forks(events)) == twins)
        }
    }

    /// A device withholds one event and signs two events at a later position, one for each of two peers. Any view
    /// that merges both peers' events reports the fork, in any delivery order.
    static let withheldAndForked = Generator(run: { rng in
        let count = Int.random(in: 3...6, using: &rng)
        let withheld = Int.random(in: 2...(count - 1), using: &rng)
        let forkAt = Int.random(in: (withheld + 1)...count, using: &rng)
        let key = EventFixture.founderMac
        guard let chain = try? EventFixture.chain(key, EventFixture.groupLabel, count: count),
            let twin = variant(of: chain[forkAt - 1], key, body: "for the other peer").first
        else { return ([Event](), [Event](), UInt64(0)) }
        let shared = chain.enumerated().filter { $0.offset + 1 != withheld }.map(\.element)
        let peerA = shared
        let peerB = shared.filter { $0.id != chain[forkAt - 1].id } + [twin]
        return (peerA, peerB.shuffled(using: &rng), UInt64(forkAt))
    })

    static func aForkBehindAWithheldEventIsSeenByMergedViews(_ algebra: LedgerAlgebra) async {
        await propertyCheck(count: 100, input: withheldAndForked) { peerA, peerB, forkAt in
            #expect(algebra.forks(peerA + peerB).map(\.sequence).contains(forkAt))
            #expect(algebra.forks(peerB + peerA).map(\.sequence).contains(forkAt))
            #expect(!algebra.forks(peerA).map(\.sequence).contains(forkAt))
        }
    }
}

/// How a ledger turns a delivery sequence into a view and its forks: `kernel`, or a planted break.
struct LedgerAlgebra: Sendable {
    var view: @Sendable ([Event]) -> LedgerView
    var forks: @Sendable ([Event]) -> [StreamPosition]

    static let kernel = LedgerAlgebra(
        view: { EventFixture.ledger($0).view },
        forks: { EventFixture.ledger($0).view.forks.map(\.position) })

    /// p2panda `ingest/operation.rs:174-190`: the first event seen at a position wins; later ones are dropped.
    static let firstSeenWins = LedgerAlgebra(
        view: { EventFixture.ledger(firstSeen($0)).view },
        forks: { EventFixture.ledger(firstSeen($0)).view.forks.map(\.position) })

    /// Review 1 F2: forks are found only where the accepted chain stops.
    static let forksOnlyWhereTheChainStops = LedgerAlgebra(
        view: kernel.view,
        forks: { events in
            let view = EventFixture.ledger(events).view
            return view.forks.map(\.position).filter { $0.sequence == UInt64(view.accepted[$0.stream]?.count ?? 0) + 1 }
        })

    private static func firstSeen(_ events: [Event]) -> [Event] {
        var seen = Set<StreamPosition>()
        return events.filter { seen.insert($0.header.position).inserted }
    }
}
