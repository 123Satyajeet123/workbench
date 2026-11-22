import Kernel
import Testing

@Suite struct EventHeaderTests {
    private let key = EventFixture.founderMac
    private let label = EventFixture.groupLabel

    @Test func theFirstEventOfAStreamHasSequenceOneAndNoBacklink() throws {
        #expect(throws: EventError.sequenceZero) {
            try EventFixture.header(key, label, sequence: 0, millis: 1, backlink: .zero)
        }
        #expect(throws: EventError.genesisWithBacklink) {
            try EventFixture.header(key, label, sequence: 1, millis: 1, backlink: EventFixture.commitment("x"))
        }
        #expect(throws: Never.self) { try EventFixture.header(key, label, sequence: 1, millis: 1, backlink: .zero) }
    }

    @Test func everyLaterEventNamesABacklink() throws {
        #expect(throws: EventError.missingBacklink) {
            try EventFixture.header(key, label, sequence: 2, millis: 1, backlink: .zero)
        }
        #expect(throws: Never.self) {
            try EventFixture.header(key, label, sequence: 2, millis: 1, backlink: EventFixture.commitment("x"))
        }
    }

    @Test func onlyTheStreamsOwnDeviceKeyMaySign() throws {
        let header = try EventFixture.header(key, label, sequence: 1, millis: 1, backlink: .zero)
        #expect(throws: EventError.deviceMismatch) { try Event(signing: header, with: EventFixture.adityaMac) }
        #expect(throws: Never.self) { try Event(signing: header, with: key) }
    }

    @Test func theIdCoversTheSignedBytesAndNotTheSignature() throws {
        let header = try EventFixture.header(key, label, sequence: 1, millis: 1, backlink: .zero)
        let first = try Event(signing: header, with: key)
        let second = try Event(signing: header, with: key)
        #expect(first.id == second.id)
        #expect(first.id == Digest.sha256(header.signedBytes))
        let other = try EventFixture.header(key, label, sequence: 1, millis: 2, backlink: .zero)
        #expect(try Event(signing: other, with: key).id != first.id)
    }

    @Test func aDeviceIdIsTheDigestOfItsPublicKey() throws {
        #expect(key.publicKey.id != EventFixture.adityaMac.publicKey.id)
        let again = try DeviceSigningKey(rawRepresentation: key.rawRepresentation)
        #expect(again.publicKey.id == key.publicKey.id)
        #expect(throws: EventError.malformed) { try DeviceSigningKey(rawRepresentation: [1, 2, 3]) }
    }

    /// The worked example of research K7 §6.4 in this layout, computed apart from this code (Python hashlib), so a
    /// change to the signed bytes cannot pass unnoticed.
    @Test func theSignedBytesAndTheIdArePinned() throws {
        let header = try EventHeader(
            stream: StreamID(
                device: try #require(DeviceID(bytes: Array(repeating: 0xA1, count: 16))),
                label: try #require(LabelID(bytes: Array(repeating: 0xB2, count: 16)))),
            sequence: 7, hlc: try #require(HybridTimestamp(millis: 1_795_305_600_000, counter: 3)),
            backlink: .sha256(Array("previous event bytes (test)".utf8)), kind: EventKind(rawValue: 1),
            commitment: .sha256(Array("body".utf8)))
        let expected =
            "00000012776f726b62656e63682e6576656e742e76320000000102000000010100000010a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"
            + "00000010b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b20000000800000000000000070000000801a2008d7400000300000020"
            + "54a64f849b0062e4358cb9cf28bd1cbfc7483d03a71391634a52a5660af9240c00000002000100000020230d8358dc8e"
            + "8890b4c58deeb62912ee2f20357ae92a5cc861b98e68fe31acb5"
        #expect(
            header.signedBytes.map { String($0 >> 4, radix: 16) + String($0 & 0xF, radix: 16) }.joined() == expected)
        #expect(
            Digest.sha256(header.signedBytes).description
                == "bfecf02eeae5e425e1a109357f30354627261c038048d5902d4b540db4a4c169")
    }

    @Test func aPublicKeyIsReadBackFromItsBytes() throws {
        #expect(try DevicePublicKey(ed25519: key.publicKey.rawRepresentation) == key.publicKey)
        #expect(throws: EventError.malformed) { try DevicePublicKey(ed25519: [1, 2, 3]) }
    }
}

@Suite struct EventWireTests {
    private let event: Event

    init() throws { event = try EventFixture.chain(EventFixture.founderMac, EventFixture.groupLabel, count: 2)[1] }

    @Test func wireBytesRoundTrip() throws {
        #expect(try Event(wireBytes: event.wireBytes) == event)
    }

    /// Research 47 I1: any changed byte is refused, by the decoder or by the signature check.
    @Test func everyChangedByteIsRefused() throws {
        let wire = event.wireBytes
        var accepted: [Int] = []
        for index in wire.indices {
            for mask: UInt8 in [0x01, 0x80] {
                var changed = wire
                changed[index] ^= mask
                var ledger = Ledger(keys: EventFixture.keys)
                guard let decoded = try? Event(wireBytes: changed), (try? ledger.insert(decoded)) != nil else {
                    continue
                }
                accepted.append(index)
            }
        }
        #expect(accepted.isEmpty)
    }

    @Test func aShortenedOrLengthenedMessageIsRefused() {
        #expect(throws: EventError.malformed) { try Event(wireBytes: Array(event.wireBytes.dropLast())) }
        #expect(throws: EventError.malformed) { try Event(wireBytes: event.wireBytes + [0]) }
        #expect(throws: EventError.malformed) { try Event(wireBytes: event.wireBytes + [0, 0, 0, 0]) }
        #expect(throws: EventError.malformed) { try Event(wireBytes: []) }
    }

    @Test func anUnknownVersionOrAlgorithmIsRefused() throws {
        let versionAt = try #require(Self.offset(of: event.header.signedBytes, part: 1, in: event.wireBytes))
        var newer = event.wireBytes
        newer[versionAt] = EventHeader.version + 1
        #expect(throws: EventError.unsupportedVersion) { try Event(wireBytes: newer) }
        var otherAlgorithm = event.wireBytes
        otherAlgorithm[versionAt + 5] = 9
        #expect(throws: EventError.unsupportedAlgorithm) { try Event(wireBytes: otherAlgorithm) }
    }

    /// The offset in `wire` of the first byte of part `part` of the framed `signed` bytes (part 0 is the tag).
    private static func offset(of signed: [UInt8], part: Int, in wire: [UInt8]) -> Int? {
        guard let start = wire.indices.first(where: { wire[$0...].starts(with: signed) }) else { return nil }
        var cursor = start
        for _ in 0..<part {
            let length = signed[(cursor - start)..<(cursor - start + 4)].reduce(0) { $0 << 8 | Int($1) }
            cursor += 4 + length
        }
        return cursor + 4
    }
}

@Suite struct EventSignatureTests {
    @Test func anEventFromAnUnknownDeviceIsRefused() throws {
        let event = try EventFixture.chain(EventFixture.stranger, EventFixture.groupLabel, count: 1)[0]
        var ledger = Ledger(keys: EventFixture.keys)
        #expect(throws: EventError.unknownDevice) { try ledger.insert(event) }
        var withStranger = Ledger(keys: EventFixture.keys + [EventFixture.stranger.publicKey])
        #expect(throws: Never.self) { try withStranger.insert(event) }
    }

    @Test func aSignatureFromAnotherEventIsRefused() throws {
        let chain = try EventFixture.chain(EventFixture.founderMac, EventFixture.groupLabel, count: 2)
        let forged = Event(header: chain[1].header, signature: chain[0].signature)
        var ledger = Ledger(keys: EventFixture.keys)
        #expect(throws: EventError.badSignature) { try ledger.insert(forged) }
        #expect(ledger.view == Ledger(keys: EventFixture.keys).view)
        #expect(throws: Never.self) { try ledger.insert(chain[1]) }
    }
}
