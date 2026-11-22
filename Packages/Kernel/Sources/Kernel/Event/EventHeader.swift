// Source: ports p2panda p2panda-core/src/operation/header.rs:41-93 (header fields) and validation.rs:51-79 (sequence and
// backlink rules), with the domain tag and the per-(device, label) stream of research 48 §1 and K2 §6.3.

/// One device's log for one label. Sequence numbers count per stream.
public struct StreamID: Hashable, Comparable, Sendable {
    public let device: DeviceID
    public let label: LabelID

    public init(device: DeviceID, label: LabelID) {
        self.device = device
        self.label = label
    }

    public static func < (lhs: StreamID, rhs: StreamID) -> Bool { (lhs.device, lhs.label) < (rhs.device, rhs.label) }
}

/// One position in a stream.
public struct StreamPosition: Hashable, Comparable, Sendable {
    public let stream: StreamID
    public let sequence: UInt64

    public init(stream: StreamID, sequence: UInt64) {
        self.stream = stream
        self.sequence = sequence
    }

    public static func < (lhs: StreamPosition, rhs: StreamPosition) -> Bool {
        (lhs.stream, lhs.sequence) < (rhs.stream, rhs.sequence)
    }
}

/// What an event is, as a number the kernel carries and does not read.
public struct EventKind: Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
}

/// The signed part of an event. The body stays outside, bound by `commitment`. A header that breaks the sequence
/// rules cannot be made.
public struct EventHeader: Hashable, Sendable {
    public static let version: UInt8 = 2
    static let domain = "workbench.event.v2"

    public let algorithm: SignatureAlgorithm
    public let stream: StreamID
    public let sequence: UInt64
    public let hlc: HybridTimestamp
    public let backlink: EventID
    public let kind: EventKind
    public let commitment: Digest

    /// The first event of a stream has sequence 1 and a zero backlink; every later one names its predecessor.
    public init(
        stream: StreamID, sequence: UInt64, hlc: HybridTimestamp, backlink: EventID, kind: EventKind,
        commitment: Digest, algorithm: SignatureAlgorithm = .ed25519
    ) throws(EventError) {
        guard sequence > 0 else { throw .sequenceZero }
        guard sequence > 1 || backlink == .zero else { throw .genesisWithBacklink }
        guard sequence == 1 || backlink != .zero else { throw .missingBacklink }
        self.algorithm = algorithm
        self.stream = stream
        self.sequence = sequence
        self.hlc = hlc
        self.backlink = backlink
        self.kind = kind
        self.commitment = commitment
    }

    public var position: StreamPosition { StreamPosition(stream: stream, sequence: sequence) }

    /// The bytes the device signs: every field, length-prefixed, under the event domain tag.
    public var signedBytes: [UInt8] {
        Framing.bytes(
            Self.domain,
            [
                [Self.version], [algorithm.rawValue], stream.device.bytes, stream.label.bytes,
                BigEndian.bytes(sequence), BigEndian.bytes(hlc.rawValue), backlink.bytes,
                BigEndian.bytes(kind.rawValue), commitment.bytes,
            ])
    }

    /// Reads back what `signedBytes` wrote. Every field must have its exact width.
    init(signedBytes: [UInt8]) throws(EventError) {
        guard let parts = Framing.parts(of: signedBytes, domain: Self.domain, count: 9) else { throw .malformed }
        guard parts[0] == [Self.version] else { throw .unsupportedVersion }
        guard parts[1].count == 1, let algorithm = SignatureAlgorithm(rawValue: parts[1][0]) else {
            throw .unsupportedAlgorithm
        }
        guard let device = DeviceID(bytes: parts[2]), let label = LabelID(bytes: parts[3]),
            parts[4].count == 8, let sequence = BigEndian.integer(UInt64.self, parts[4]),
            parts[5].count == 8, let packed = BigEndian.integer(Int64.self, parts[5]),
            let hlc = HybridTimestamp(rawValue: packed), let backlink = EventID(bytes: parts[6]),
            parts[7].count == 2, let kind = BigEndian.integer(UInt16.self, parts[7]),
            let commitment = Digest(bytes: parts[8])
        else { throw .malformed }
        try self.init(
            stream: StreamID(device: device, label: label), sequence: sequence, hlc: hlc, backlink: backlink,
            kind: EventKind(rawValue: kind), commitment: commitment, algorithm: algorithm)
    }
}
