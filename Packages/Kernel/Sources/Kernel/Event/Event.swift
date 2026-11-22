// Source: ports p2panda p2panda-core/src/operation/validation.rs:51-79 (verify the signature against the author key)
// and judgment-pilot Packages/WorkbenchCore/Sources/WorkbenchCore/Team/Sync/Envelope.swift:46-51 (domain-tagged
// signature; the signer must be the author).

/// A signed header. Its id is the digest of the signed bytes, so the same header signed twice is one event.
public struct Event: Hashable, Sendable {
    static let wireDomain = "workbench.event.wire.v2"
    static let signatureSize = 64

    public let header: EventHeader
    public let signature: [UInt8]
    public let id: EventID

    /// An event as received, not yet verified. `Ledger.insert` verifies it.
    public init(header: EventHeader, signature: [UInt8]) {
        self.header = header
        self.signature = signature
        id = .sha256(header.signedBytes)
    }

    /// Signs `header` with the key of the device that owns its stream.
    public init(signing header: EventHeader, with key: DeviceSigningKey) throws(EventError) {
        guard key.publicKey.id == header.stream.device else { throw .deviceMismatch }
        self.init(header: header, signature: try key.sign(header.signedBytes))
    }

    /// The bytes that travel: the signed bytes and the signature, framed.
    public var wireBytes: [UInt8] { Framing.bytes(Self.wireDomain, [header.signedBytes, signature]) }

    /// Reads back what `wireBytes` wrote. It checks the form only; `Ledger.insert` checks the signature.
    public init(wireBytes: [UInt8]) throws(EventError) {
        guard let parts = Framing.parts(of: wireBytes, domain: Self.wireDomain, count: 2),
            parts[1].count == Self.signatureSize
        else { throw .malformed }
        self.init(header: try EventHeader(signedBytes: parts[0]), signature: parts[1])
    }

    /// True when `key` made the signature over the signed bytes.
    func isSigned(by key: DevicePublicKey) -> Bool { key.verifies(signature, over: header.signedBytes) }
}

public enum EventError: Error, Equatable, Sendable {
    case malformed
    case unsupportedVersion
    case unsupportedAlgorithm
    case sequenceZero
    case genesisWithBacklink
    case missingBacklink
    case deviceMismatch
    case signingFailed
    case unknownDevice
    case badSignature
}
