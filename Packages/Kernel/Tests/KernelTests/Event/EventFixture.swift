import Kernel

/// Devices, labels and event chains for event tests. Keys are made once, so a property can sign many events.
enum EventFixture {
    static let founderMac = DeviceSigningKey()
    static let adityaMac = DeviceSigningKey()
    static let stranger = DeviceSigningKey()
    static let keys = [founderMac.publicKey, adityaMac.publicKey]

    static let groupLabel = Label(source: Team.foundersGroup).id
    static let dealLabel = Label(source: Team.partnerships).id

    static let note = EventKind(rawValue: 1)
    static let startMillis: Int64 = 1_795_305_600_000

    static func commitment(_ text: String) -> Digest { Digest.sha256(Array(text.utf8)) }

    static func header(
        _ key: DeviceSigningKey, _ label: LabelID, sequence: UInt64, millis: Int64, backlink: Digest,
        body: String = "body"
    ) throws -> EventHeader {
        try EventHeader(
            stream: StreamID(device: key.publicKey.id, label: label), sequence: sequence,
            hlc: HybridTimestamp(millis: millis, counter: 0) ?? .zero, backlink: backlink, kind: note,
            commitment: commitment(body))
    }

    /// A valid chain of `count` events, one millisecond apart.
    static func chain(_ key: DeviceSigningKey, _ label: LabelID, count: Int, body: String = "body") throws -> [Event] {
        var events: [Event] = []
        for sequence in 1...UInt64(count) {
            let backlink = events.last?.id ?? .zero
            let millis = startMillis + Int64(sequence)
            let made = try header(key, label, sequence: sequence, millis: millis, backlink: backlink, body: body)
            events.append(try Event(signing: made, with: key))
        }
        return events
    }

    static func ledger(_ events: [Event]) -> Ledger {
        var ledger = Ledger(keys: keys)
        for event in events { try? ledger.insert(event) }
        return ledger
    }
}
