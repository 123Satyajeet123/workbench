// Source: built (ADR-014: one SHA-256 name type per domain tag).

import Kernel

/// The domain tag of one kind of name.
public protocol HashDomain: Sendable {
    static var tag: String { get }
}

/// A SHA-256 over parts framed under `Domain.tag`. Names of different domains are different types.
public struct DomainHash<Domain: HashDomain>: FixedBytes {
    public static var count: Int { Digest.count }
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.count else { return nil }
        self.bytes = bytes
    }

    init(parts: [[UInt8]]) { bytes = Digest.framed(Domain.tag, parts).bytes }
}

public enum ContentDomain: HashDomain { public static let tag = "workbench.content.v1" }
public enum TombstoneDomain: HashDomain { public static let tag = "workbench.tombstone.v1" }
public enum LineDomain: HashDomain { public static let tag = "workbench.line.v1" }
public enum ViewDomain: HashDomain { public static let tag = "workbench.view.v1" }
public enum AudienceDomain: HashDomain { public static let tag = "workbench.audience.v1" }

/// The hash of what a line says: its identity text under `workbench.content.v1`, or, for a tombstone (a message
/// deleted at its source), the empty part list under `workbench.tombstone.v1`.
public typealias ContentHash = DomainHash<ContentDomain>

/// The id of a line: its entity key and content hash under `workbench.line.v1`.
public typealias LineID = DomainHash<LineDomain>

/// The id of one ordered read of a container: the container and its line ids in reading order under
/// `workbench.view.v1`.
public typealias ViewID = DomainHash<ViewDomain>

/// Who could read a line when it was captured: the owner and the active members, each named once, under
/// `workbench.audience.v1`.
public typealias AudienceDigest = DomainHash<AudienceDomain>

extension DomainHash where Domain == ContentDomain {
    public init(text: String) { self.init(identityText: IdentityText.normalize(text)) }

    init(identityText: String) { self.init(parts: [Array(identityText.utf8)]) }

    /// The content of every tombstone. No text has this hash.
    public static let tombstone = ContentHash(bytes: Digest.framed(TombstoneDomain.tag, []).bytes)!
}

extension DomainHash where Domain == LineDomain {
    public init(entity: EntityKey, content: ContentHash) { self.init(parts: [entity.bytes, content.bytes]) }
}

extension DomainHash where Domain == ViewDomain {
    public init(container: String, lines: [LineID]) {
        self.init(parts: [Array(container.precomposedStringWithCanonicalMapping.utf8)] + lines.map(\.bytes))
    }
}

extension DomainHash where Domain == AudienceDomain {
    /// Member ids are NFC and compared by their UTF-8 bytes; order and repeats do not matter, and the owner is a
    /// member. Give canonical ids (for WhatsApp, `WhatsAppJID.canonical`).
    public init(owner: String, members: some Sequence<String>) {
        let ids = Set(([owner] + members).map { Array($0.precomposedStringWithCanonicalMapping.utf8) })
        self.init(parts: ids.sorted { $0.lexicographicallyPrecedes($1) })
    }
}
