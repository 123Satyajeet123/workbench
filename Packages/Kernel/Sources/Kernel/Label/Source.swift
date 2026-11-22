// Source: built (review 1 F4, orchestrator decision 2026-11-22: a source id is derived from its owner).

/// One source of evidence: its owner, and the owner's own key for it.
public struct Source: Hashable, Sendable {
    public let owner: PersonID
    public let key: SourceKey

    public init(owner: PersonID, key: SourceKey) {
        self.owner = owner
        self.key = key
    }

    public var id: SourceID { SourceID(of: self) }
}

/// A source, named by the first 16 bytes of SHA-256 over its owner and key. Two owners never share a source id, and
/// the owner of an id is checked by recomputing it.
public struct SourceID: FixedBytes {
    public static let count = 16
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.count else { return nil }
        self.bytes = bytes
    }

    fileprivate init(of source: Source) {
        let digest = Digest.framed("workbench.source.v1", [source.owner.utf8Bytes, source.key.utf8Bytes])
        bytes = Array(digest.bytes.prefix(Self.count))
    }
}
