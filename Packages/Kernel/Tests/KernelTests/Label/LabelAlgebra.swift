import Kernel

/// The label operations a law or a ported case is checked against. `kernel` is the code under test; every other
/// value is a planted break: one deliberately wrong operation, named after the real defect it replays.
struct LabelAlgebra: Sendable {
    var join: @Sendable (Label, Label) -> Label
    var readers: @Sendable (Label, [Grant], Roster) -> Set<PersonID>
    var admits: @Sendable (Label, Set<PersonID>, [Grant], Roster) -> Bool
    var release: @Sendable (Label, Release, [Grant]) -> Label?
    var labelOfExtraction: @Sendable (Extraction) -> Label

    static let kernel = LabelAlgebra(
        join: { $0.joined(with: $1) },
        readers: { $0.readers(grants: Grants($1), roster: $2) },
        admits: { $0.admits($1, grants: Grants($2), roster: $3) },
        release: { try? $0.released(by: $1, grants: Grants($2)) },
        labelOfExtraction: { $0.window[0].joined(with: $0.window.dropFirst()) }
    )
}

extension LabelAlgebra {
    static let joinDropsRightClasses = kernel.with(join: { left, right in
        rebuilt(left.joined(with: right), classes: left.classes)
    })

    /// Research K6 R3: past a size cap the derived item keeps its own (left) label.
    static let joinFallsBackToOwnLabelPastACap = kernel.with(join: { left, right in
        let joined = left.joined(with: right)
        return joined.sources.count > 3 ? left : joined
    })

    static let joinTagsResultAsDerived = kernel.with(join: { left, right in
        let joined = left.joined(with: right)
        return rebuilt(joined, classes: joined.classes.union([sourceClass("derived")]))
    })

    static let readersUnionOverSources = kernel.with(readers: { label, grants, roster in
        let resolved = Grants(grants)
        let perSource = label.sources.map { resolved.current(for: $0)?.readers ?? [] }
        return perSource.reduce(into: Set()) { $0.formUnion($1) }.intersection(roster.members)
    })

    /// Research K5 T3: a summary takes its first input's label.
    static let readersOfFirstSourceOnly = kernel.with(readers: { label, grants, roster in
        guard let first = label.sources.min() else { return [] }
        return Label(source: first).readers(grants: Grants(grants), roster: roster)
    })

    /// Research K5 T14 and qm `memory-disclosure.test.ts:265-280`: a grant cached from an older epoch.
    static let readersUseOldestGrant = kernel.with(readers: { label, grants, roster in
        let oldest = Dictionary(grouping: grants, by: \.source).compactMap { $0.value.min { $0.epoch < $1.epoch } }
        return label.readers(grants: Grants(oldest), roster: roster)
    })

    static let readersIgnoreRoster = kernel.with(readers: { label, grants, _ in
        label.readers(grants: Grants(grants), roster: Roster(members: Set(LabelWorld.people + Team.everyone)))
    })

    /// Research K6 R2 (`TeamSync.swift:61`): a missing audience means the whole team.
    static let missingGrantReadsAsWholeRoster = kernel.with(readers: { label, grants, roster in
        let resolved = Grants(grants)
        return label.sources.reduce(roster.members) { readers, source in
            readers.intersection(resolved.current(for: source)?.readers ?? roster.members)
        }
    })

    /// Review 1 F4: a grant counts whoever signed it, so a stranger's newer grant replaces the owner's.
    static let grantSignerIgnored = kernel.with(readers: { label, grants, roster in
        let ownerSigned = grants.map {
            Grant(signer: $0.source.owner, source: $0.source, readers: $0.readers, epoch: $0.epoch)
        }
        return label.readers(grants: Grants(ownerSigned), roster: roster)
    })

    /// qm `memory-disclosure.test.ts:282-304`: an audience is trimmed to its readers instead of refused whole.
    static let admitsTrimsTheAudience = kernel.with(admits: { label, audience, grants, roster in
        !audience.isDisjoint(with: label.readers(grants: Grants(grants), roster: roster))
    })

    /// Research 45 §4 as first written: a fact's label is the join of the cited lines only.
    static let labelFromCitedLinesOnly = kernel.with(labelOfExtraction: { extraction in
        let cited = extraction.output.cited.sorted().map { extraction.window[$0] }
        guard let first = cited.first else { return extraction.window[0] }
        return first.joined(with: cited.dropFirst())
    })

    /// Research K5 T6: a release signed by the owner of some other source in the label.
    static let releaseByAnyOwnerInLabel = kernel.with(release: { label, release, grants in
        let resolved = Grants(grants)
        let owners = Set(label.sources.compactMap { resolved.current(for: $0)?.source.owner })
        guard owners.contains(release.signer), label.sources.contains(release.covers),
            resolved.current(for: release.to)?.source.owner == release.signer
        else { return nil }
        return rebuilt(label, replacing: release)
    })

    /// agentes-chat `items.ts:927-949`: anyone with the reviewer role may open an item.
    static let releaseBySomeoneWithTheRole = kernel.with(release: { label, release, _ in
        label.sources.contains(release.covers) ? rebuilt(label, replacing: release) : nil
    })
}

extension LabelAlgebra {
    fileprivate func with(join: @escaping @Sendable (Label, Label) -> Label) -> LabelAlgebra {
        var copy = self
        copy.join = join
        return copy
    }

    /// Replaces `readers`, and `admits` with it, since an audience is admitted against the readers.
    fileprivate func with(readers: @escaping @Sendable (Label, [Grant], Roster) -> Set<PersonID>) -> LabelAlgebra {
        var copy = self
        copy.readers = readers
        copy.admits = { label, audience, grants, roster in
            !audience.isEmpty && audience.isSubset(of: readers(label, grants, roster))
        }
        return copy
    }

    fileprivate func with(admits: @escaping @Sendable (Label, Set<PersonID>, [Grant], Roster) -> Bool) -> LabelAlgebra {
        var copy = self
        copy.admits = admits
        return copy
    }

    fileprivate func with(release: @escaping @Sendable (Label, Release, [Grant]) -> Label?) -> LabelAlgebra {
        var copy = self
        copy.release = release
        return copy
    }

    fileprivate func with(labelOfExtraction: @escaping @Sendable (Extraction) -> Label) -> LabelAlgebra {
        var copy = self
        copy.labelOfExtraction = labelOfExtraction
        return copy
    }
}

private func rebuilt(_ label: Label, classes: Set<SourceClass>) -> Label {
    (try? Label(sources: label.sources, classes: classes)) ?? label
}

private func rebuilt(_ label: Label, replacing release: Release) -> Label {
    let sources = label.sources.subtracting([release.covers]).union([release.to])
    return (try? Label(sources: sources, classes: label.classes)) ?? label
}
