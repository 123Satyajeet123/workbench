// Source: built (research K5 §5.1-5.2; decentralized label model declassification, Myers-Liskov TOSEM 2000 §3.6).

/// An owner's rule that relaxes one source of a label: the covered source is replaced by a release source whose
/// grant names the people the owner chose, such as a role.
public struct Release: Hashable, Sendable {
    public let signer: PersonID
    public let covers: SourceID
    public let to: SourceID

    public init(signer: PersonID, covers: SourceID, to: SourceID) {
        self.signer = signer
        self.covers = covers
        self.to = to
    }
}

public enum ReleaseError: Error, Equatable, Sendable {
    case sourceNotInLabel
    case noCurrentGrant
    case signerIsNotOwner
    case targetNotOwnedBySigner
}

extension Label {
    /// This label with `release.covers` replaced by `release.to`. Only the owner of the covered source may release
    /// it, and only into a source they own. Classes and every other source stay.
    public func released(by release: Release, grants: Grants) throws(ReleaseError) -> Label {
        guard sources.contains(release.covers) else { throw .sourceNotInLabel }
        guard let covered = grants.current(for: release.covers) else { throw .noCurrentGrant }
        guard covered.source.owner == release.signer else { throw .signerIsNotOwner }
        guard grants.current(for: release.to)?.source.owner == release.signer else { throw .targetNotOwnedBySigner }
        let kept = sources.subtracting([release.covers]).map { Label(source: $0) }
        return Label(source: release.to, classes: classes).joined(with: kept)
    }
}
