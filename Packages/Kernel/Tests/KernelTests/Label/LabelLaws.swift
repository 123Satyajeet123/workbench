import Kernel
import PropertyBased
import Testing

/// The label laws of research K5 §3.2, each a property over random labels, grants and rosters. Each takes the
/// algebra to check, so one law runs both on the kernel and on its planted break.
enum LabelLaws {
    static let cases = 300

    /// T1: join is commutative.
    static func joinIsCommutative(_ algebra: LabelAlgebra) async {
        await propertyCheck(count: cases, input: LabelWorld.label, LabelWorld.label) { a, b in
            #expect(algebra.join(a, b) == algebra.join(b, a))
        }
    }

    /// T1: join is associative.
    static func joinIsAssociative(_ algebra: LabelAlgebra) async {
        await propertyCheck(count: cases, input: LabelWorld.label, LabelWorld.label, LabelWorld.label) { a, b, c in
            #expect(algebra.join(algebra.join(a, b), c) == algebra.join(a, algebra.join(b, c)))
        }
    }

    /// T1: join is idempotent.
    static func joinIsIdempotent(_ algebra: LabelAlgebra) async {
        await propertyCheck(count: cases, input: LabelWorld.label) { a in
            #expect(algebra.join(a, a) == a)
        }
    }

    /// L1: readers(a ⊔ b) = readers(a) ∩ readers(b), for every grant state and roster.
    static func readersOfAJoinAreTheIntersection(_ algebra: LabelAlgebra) async {
        await propertyCheck(
            count: cases, input: LabelWorld.label, LabelWorld.label, LabelWorld.grants, LabelWorld.roster
        ) { a, b, grants, roster in
            let joined = algebra.readers(algebra.join(a, b), grants, roster)
            #expect(joined == algebra.readers(a, grants, roster).intersection(algebra.readers(b, grants, roster)))
        }
    }

    /// L2: if a ⊑ b then readers(b) ⊆ readers(a).
    static func derivationOnlyNarrows(_ algebra: LabelAlgebra) async {
        await propertyCheck(
            count: cases, input: LabelWorld.label, LabelWorld.label, LabelWorld.grants, LabelWorld.roster
        ) { a, extra, grants, roster in
            let derived = algebra.join(a, extra)
            #expect(algebra.readers(derived, grants, roster).isSubset(of: algebra.readers(a, grants, roster)))
        }
    }

    /// L3: a newer, narrower grant for one source narrows exactly the labels that hold that source, by exactly the
    /// people it drops.
    static func narrowingAGrantNarrowsExactlyItsLabels(_ algebra: LabelAlgebra) async {
        await propertyCheck(
            count: cases, input: LabelWorld.label, LabelWorld.grants, LabelWorld.roster, LabelWorld.readerSet,
            pick(LabelWorld.sources)
        ) { label, grants, roster, keep, source in
            guard let current = Grants(grants).current(for: source) else { return }
            let narrowed = Grant(
                signer: current.signer, source: current.source, readers: current.readers.intersection(keep),
                epoch: current.epoch + 1)
            let before = algebra.readers(label, grants, roster)
            let after = algebra.readers(label, grants + [narrowed], roster)
            let expected = label.sources.contains(source) ? before.intersection(narrowed.readers) : before
            #expect(after == expected)
        }
    }

    /// L4: removing a person from the roster removes them from every reader set, and nobody else.
    static func leavingTheRosterRemovesTheReader(_ algebra: LabelAlgebra) async {
        await propertyCheck(count: cases, input: LabelWorld.label, LabelWorld.grants, LabelWorld.roster) {
            label, grants, roster in
            let before = algebra.readers(label, grants, roster)
            guard let leaver = before.min() ?? roster.members.min() else { return }
            let after = algebra.readers(label, grants, Roster(members: roster.members.subtracting([leaver])))
            #expect(after == before.subtracting([leaver]))
        }
    }

    /// L5 and window taint (K5 T4, T5): the label of a model's output is the join of every line it saw. What the
    /// model cites or says changes nothing.
    static func outputLabelIgnoresTheModel(_ algebra: LabelAlgebra) async {
        let otherOutput = zip(Gen.int(in: 0...4).set(ofAtMost: 0...4), pick(["note", "risk"]))
            .map { ModelOutput(cited: $0, kind: $1) }
        await propertyCheck(count: cases, input: LabelWorld.extraction, otherOutput) { extraction, other in
            var rerun = extraction
            rerun.output = ModelOutput(cited: other.cited.filter { $0 < extraction.window.count }, kind: other.kind)
            let label = algebra.labelOfExtraction(extraction)
            #expect(label == algebra.labelOfExtraction(rerun))
            #expect(extraction.window.allSatisfy { $0.sources.isSubset(of: label.sources) })
        }
    }

    /// L6: readers widen only through a release signed by the owner of the source it relaxes, into a source that
    /// owner also owns. The property must see real releases: at least one case in twenty succeeds.
    static func onlyTheOwnerWidens(_ algebra: LabelAlgebra) async {
        var released = 0
        await propertyCheck(
            count: cases, input: LabelWorld.summaryAndRelease, LabelWorld.grants, LabelWorld.roster
        ) { summaryAndRelease, grants, roster in
            let (label, release) = summaryAndRelease
            guard let result = algebra.release(label, release, grants) else { return }
            released += 1
            let widened = algebra.readers(result, grants, roster).subtracting(algebra.readers(label, grants, roster))
            let resolved = Grants(grants)
            let signerOwnsBoth = [release.covers, release.to].allSatisfy {
                resolved.current(for: $0)?.source.owner == release.signer
            }
            #expect(widened.isEmpty || signerOwnsBoth)
        }
        #expect(released >= cases / 20, "only \(released) of \(cases) cases released anything")
    }

    /// L7: a source with no grant, two owner grants that disagree, only grants by strangers, or an empty roster
    /// gives no readers.
    static func unknownGivesNobody(_ algebra: LabelAlgebra) async {
        let breakage = Gen<GrantBreakage>.case
        await propertyCheck(
            count: cases, input: LabelWorld.label, LabelWorld.grants, LabelWorld.roster, breakage
        ) { label, grants, roster, breakage in
            guard let source = label.sources.min() else { return }
            let (brokenGrants, brokenRoster) = breakage.apply(to: grants, roster: roster, at: source)
            #expect(algebra.readers(label, brokenGrants, brokenRoster).isEmpty)
        }
    }

    /// Review 1 F4: grants signed by someone other than the source's owner change no reader set.
    static func strangersChangeNothing(_ algebra: LabelAlgebra) async {
        await propertyCheck(
            count: cases, input: LabelWorld.label, LabelWorld.grants, LabelWorld.roster, LabelWorld.strangerGrants
        ) { label, grants, roster, strangers in
            #expect(algebra.readers(label, grants + strangers, roster) == algebra.readers(label, grants, roster))
        }
    }

    /// OpenAPPA `label.rs:1214` `nobody_absorbs`: a part nobody may read absorbs every join, in every grant state.
    static func aPartNobodyReadsAbsorbsEveryJoin(_ algebra: LabelAlgebra) async {
        let untracked = Label(source: source(LabelWorld.people[0], "untracked").id)
        await propertyCheck(count: cases, input: LabelWorld.label, LabelWorld.grants, LabelWorld.roster) {
            label, grants, roster in
            #expect(algebra.readers(algebra.join(label, untracked), grants, roster).isEmpty)
        }
    }

    /// OpenAPPA `label.rs:1252` `combine_never_widens`: a join is read by no one who could not read each part.
    static func aJoinNeverWidensEitherPart(_ algebra: LabelAlgebra) async {
        await propertyCheck(
            count: cases, input: LabelWorld.label, LabelWorld.label, LabelWorld.grants, LabelWorld.roster
        ) { a, b, grants, roster in
            let joined = algebra.readers(algebra.join(a, b), grants, roster)
            #expect(joined.isSubset(of: algebra.readers(a, grants, roster)))
            #expect(joined.isSubset(of: algebra.readers(b, grants, roster)))
        }
    }
}

enum GrantBreakage: CaseIterable, Sendable {
    case missing, sameEpochDisagrees, onlyStrangers, emptyRoster

    func apply(to grants: [Grant], roster: Roster, at source: SourceID) -> ([Grant], Roster) {
        let others = grants.filter { $0.source.id != source }
        let value = LabelWorld.sourceValue(of: source)
        let stranger = LabelWorld.people.first { $0 != value.owner } ?? value.owner
        let everyone = Set(LabelWorld.people)
        switch self {
        case .missing:
            return (others, roster)
        case .sameEpochDisagrees:
            let rival = [
                Grant(signer: value.owner, source: value, readers: everyone, epoch: 9),
                Grant(signer: value.owner, source: value, readers: [value.owner], epoch: 9),
            ]
            return (others + rival, roster)
        case .onlyStrangers:
            return (others + [Grant(signer: stranger, source: value, readers: everyone, epoch: 9)], roster)
        case .emptyRoster:
            return (grants, Roster(members: []))
        }
    }
}
