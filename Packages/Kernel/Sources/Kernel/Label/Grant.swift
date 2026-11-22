// Source: built (research K5 §2.2, Myers-Liskov decentralized label model: one policy `owner: readers` per source;
// review 1 F4: a grant counts only when its source's owner signed it).

/// A statement of who may read one source, at one epoch, and who signed it. It counts only when the signer is the
/// source's owner. A newer epoch replaces an older one.
public struct Grant: Hashable, Sendable {
    public let signer: PersonID
    public let source: Source
    public let readers: Set<PersonID>
    public let epoch: UInt64

    public init(signer: PersonID, source: Source, readers: Set<PersonID>, epoch: UInt64) {
        self.signer = signer
        self.source = source
        self.readers = readers
        self.epoch = epoch
    }

    public var isSignedByOwner: Bool { signer == source.owner }
}

/// The people on the team at one moment. A reader must be on it.
public struct Roster: Hashable, Sendable {
    public let members: Set<PersonID>

    public init(members: Set<PersonID>) { self.members = members }
}

/// The current grant of each source, resolved from every grant known. Grants not signed by their source's owner are
/// refused and kept in `refused`; they change nothing. A source whose newest epoch holds two different owner-signed
/// grants is in `conflicted` and has no current grant.
public struct Grants: Sendable {
    private let current: [SourceID: Grant]
    public let refused: Set<Grant>
    public let conflicted: Set<SourceID>

    public init(_ grants: some Sequence<Grant>) {
        let all = Array(grants)
        refused = Set(all.filter { !$0.isSignedByOwner })
        let newest = Dictionary(grouping: all.filter(\.isSignedByOwner), by: \.source.id).mapValues(Self.newest)
        current = newest.compactMapValues { $0.count == 1 ? $0.first : nil }
        conflicted = Set(newest.filter { $0.value.count > 1 }.keys)
    }

    public func current(for source: SourceID) -> Grant? { current[source] }

    private static func newest(_ grants: [Grant]) -> Set<Grant> {
        let epoch = grants.map(\.epoch).max()
        return Set(grants.filter { $0.epoch == epoch })
    }
}
