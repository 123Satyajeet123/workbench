// Source: built (review 1 F3; research 47 §4 budget: publish under 20 ms per event at 100k history).
// Run: swift run -c release KernelBenchmark

import Kernel

/// Signed chains for `streams` labels of one device, `total` events in all, one millisecond apart per stream.
func makeEvents(total: Int, streams: Int, key: DeviceSigningKey) throws -> [Event] {
    let owner = try PersonID("owner")
    let labels = try (0..<streams).map { Label(source: Source(owner: owner, key: try SourceKey("s\($0)")).id).id }
    var heads: [EventID?] = Array(repeating: nil, count: streams)
    var events: [Event] = []
    events.reserveCapacity(total)
    for index in 0..<total {
        let lane = index % streams
        let sequence = UInt64(index / streams + 1)
        let header = try EventHeader(
            stream: StreamID(device: key.publicKey.id, label: labels[lane]), sequence: sequence,
            hlc: HybridTimestamp(millis: 1_795_305_600_000 + Int64(index), counter: 0) ?? .zero,
            backlink: heads[lane] ?? .zero, kind: EventKind(rawValue: 1), commitment: .sha256([UInt8(index & 0xFF)]))
        let event = try Event(signing: header, with: key)
        heads[lane] = event.id
        events.append(event)
    }
    return events
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

/// Inserts every event, reading the view and the stream head after each one, and times the last `sample` steps.
func measure(total: Int, streams: Int, sample: Int, holdingPreviousView: Bool) throws {
    let key = DeviceSigningKey()
    let events = try makeEvents(total: total, streams: streams, key: key)
    var ledger = Ledger(keys: [key.publicKey])
    let clock = ContinuousClock()
    var times: [Double] = []
    var held: LedgerView?
    var checksum = 0
    for (index, event) in events.enumerated() {
        let start = clock.now
        try ledger.insert(event)
        let view = ledger.view
        checksum &+= view.accepted.count + Int(ledger.head(of: event.header.stream)?.sequence ?? 0)
        if holdingPreviousView && index >= total - sample - 1 { held = view }
        if index >= total - sample { times.append(milliseconds(clock.now - start)) }
    }
    times.sort()
    let mean = times.reduce(0, +) / Double(times.count)
    let accepted = ledger.view.accepted.values.map(\.count).reduce(0, +)
    let label = holdingPreviousView ? "caller keeps the previous view" : "view read and dropped"
    print(
        "events \(total), streams \(streams), \(label): insert+view+head over the last \(sample) at "
            + "\(total - sample)...\(total): median \(times[times.count / 2]) ms, p99 \(times[times.count * 99 / 100]) ms, "
            + "max \(times.last ?? 0) ms, mean \(mean) ms; accepted \(accepted), held \(held != nil), check \(checksum)"
    )
}

for streams in [1, 20] {
    for holding in [false, true] {
        try measure(total: 100_000, streams: streams, sample: 1000, holdingPreviousView: holding)
    }
}
