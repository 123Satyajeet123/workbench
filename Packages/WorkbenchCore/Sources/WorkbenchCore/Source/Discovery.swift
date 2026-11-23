import Foundation
import Lines

/// Whether a container holds two people or many.
public enum ContainerKind: String, Sendable, Equatable {
    case direct
    case group
}

/// One thing a source reads: a chat, a group, a mail thread, an event series. `id` is the source's canonical id of it,
/// so two sources that see one container give one id.
public struct Container: Sendable, Equatable, Hashable {
    public var id: String
    public var kind: ContainerKind
    public var title: String

    public init(id: String, kind: ContainerKind, title: String) {
        self.id = id
        self.kind = kind
        self.title = title
    }
}

/// Who is in a container, as one source saw it. Member ids are the source's canonical ids, never names.
public struct Membership: Sendable, Equatable {
    /// How the source knows the list.
    public enum Proof: String, Sendable {
        /// The source's own store holds the list.
        case sourceTable
    }

    /// Unique, sorted and never empty.
    public let members: [String]
    public let proof: Proof

    /// Nil when no member is left after dropping empty ids and repeats: an empty list proves nothing.
    public init?(members: some Sequence<String>, proof: Proof) {
        let unique = Set(members.map { $0.precomposedStringWithCanonicalMapping }.filter { !$0.isEmpty })
        guard !unique.isEmpty else { return nil }
        self.members = unique.sorted()
        self.proof = proof
    }
}

/// A container a source sees now. It holds no message text. `membership` is the list of members when the source saw it
/// at `observedAt`; it is valid for the reading that saw it and for no other.
public struct ContainerSighting: Sendable, Equatable {
    public var container: Container
    /// The key of the source that saw it (`SourceDescriptor.key`).
    public var source: String
    public var observedAt: Date
    public var membership: Membership?

    public init(container: Container, source: String, observedAt: Date, membership: Membership? = nil) {
        self.container = container
        self.source = source
        self.observedAt = observedAt
        self.membership = membership
    }
}

/// What every source says about its containers: which it sees now, and who is in each. Discovery gives structure and
/// never message text, and never writes the person's allow-list: choosing is the person's act.
public protocol ContainerSource: Sendable {
    var descriptor: SourceDescriptor { get }

    /// The containers this source sees now, or why it sees none.
    func sightings(policy: CapturePolicy, now: Date) throws -> [ContainerSighting]
}

/// Who could read a line: the one rule for every source.
public enum AudienceRule {
    /// A direct container is read by the owner and the other person, whom its id names. A group is read by the members
    /// of a valid observation made in the same reading. With none, nobody can say, and the answer is nil: no line.
    public static func digest(of container: Container, owner: String, membership: Membership?) -> AudienceDigest? {
        switch container.kind {
        case .direct: AudienceDigest(owner: owner, members: [container.id])
        case .group: membership.map { AudienceDigest(owner: owner, members: $0.members) }
        }
    }
}
