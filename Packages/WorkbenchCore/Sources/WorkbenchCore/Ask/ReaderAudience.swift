import Kernel

/// Who may read what, as the Kernel works it out from the sources' grants and the roster. A person owns the sources
/// this app reads for them and grants them to themselves alone, so a line of any other person's source has no current
/// grant and no reader.
struct ReaderAudience {
    let reader: PersonID
    let grants: Grants
    let roster: Kernel.Roster

    init(reader: PersonID) throws {
        self.reader = reader
        roster = Kernel.Roster(members: [reader])
        grants = Grants(
            try SourceRegistry.all.map { descriptor in
                Grant(
                    signer: reader, source: Kernel.Source(owner: reader, key: try SourceKey(descriptor.key)),
                    readers: [reader], epoch: 0)
            })
    }

    /// A line with no label of its own source is read as unlabelled, and no reader satisfies that.
    func admits(_ line: StoredLine) -> Bool {
        line.provenance?.label.admits([reader], grants: grants, roster: roster) ?? false
    }
}

extension PageViewer {
    /// The person who owns every source this app reads, as the reader of a page.
    public init(owner: PersonID) throws {
        let audience = try ReaderAudience(reader: owner)
        self.init(audience: [owner], grants: audience.grants, roster: audience.roster)
    }
}
