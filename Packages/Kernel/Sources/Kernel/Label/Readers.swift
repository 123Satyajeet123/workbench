// Source: ports qm src/memory/disclosure.ts:53-55 (every recipient entitled, audience non-empty) and agentes-chat
// packages/engine/src/context/items.ts:621-622 (every channel required).

extension Label {
    /// The people who may read this label now: those in every source's current grant, and on the roster.
    /// A source with no current grant gives no readers.
    public func readers(grants: Grants, roster: Roster) -> Set<PersonID> {
        sources.reduce(roster.members) { readers, source in
            readers.intersection(grants.current(for: source)?.readers ?? [])
        }
    }

    /// True when `audience` is not empty and every person in it may read this label. An audience with one
    /// non-reader is refused whole, never trimmed.
    public func admits(_ audience: Set<PersonID>, grants: Grants, roster: Roster) -> Bool {
        !audience.isEmpty && audience.isSubset(of: readers(grants: grants, roster: roster))
    }
}
