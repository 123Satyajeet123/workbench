import PropertyBased
import Testing

/// Each law runs twice: it must hold on the kernel, and it must fail on its planted break.
@Suite struct LabelLawTests {
    @Test func joinIsCommutative() async { await LabelLaws.joinIsCommutative(.kernel) }

    @Test(.shrinking(false)) func joinIsCommutativeCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("join drops the right label's classes") {
            await LabelLaws.joinIsCommutative(.joinDropsRightClasses)
        }
    }

    @Test func joinIsAssociative() async { await LabelLaws.joinIsAssociative(.kernel) }

    @Test(.shrinking(false)) func joinIsAssociativeCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("join keeps its own label past a size cap") {
            await LabelLaws.joinIsAssociative(.joinFallsBackToOwnLabelPastACap)
        }
    }

    @Test func joinIsIdempotent() async { await LabelLaws.joinIsIdempotent(.kernel) }

    @Test(.shrinking(false)) func joinIsIdempotentCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("join tags its result as derived") {
            await LabelLaws.joinIsIdempotent(.joinTagsResultAsDerived)
        }
    }

    @Test func readersOfAJoinAreTheIntersection() async { await LabelLaws.readersOfAJoinAreTheIntersection(.kernel) }

    @Test(.shrinking(false)) func readersOfAJoinCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("readers are the union over sources") {
            await LabelLaws.readersOfAJoinAreTheIntersection(.readersUnionOverSources)
        }
    }

    @Test func derivationOnlyNarrows() async { await LabelLaws.derivationOnlyNarrows(.kernel) }

    @Test(.shrinking(false)) func derivationOnlyNarrowsCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("readers come from the first source only") {
            await LabelLaws.derivationOnlyNarrows(.readersOfFirstSourceOnly)
        }
    }

    @Test func narrowingAGrantNarrowsExactlyItsLabels() async {
        await LabelLaws.narrowingAGrantNarrowsExactlyItsLabels(.kernel)
    }

    @Test(.shrinking(false)) func narrowingAGrantCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("readers use the oldest grant") {
            await LabelLaws.narrowingAGrantNarrowsExactlyItsLabels(.readersUseOldestGrant)
        }
    }

    @Test func leavingTheRosterRemovesTheReader() async { await LabelLaws.leavingTheRosterRemovesTheReader(.kernel) }

    @Test(.shrinking(false)) func leavingTheRosterCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("readers ignore the roster") {
            await LabelLaws.leavingTheRosterRemovesTheReader(.readersIgnoreRoster)
        }
    }

    @Test func outputLabelIgnoresTheModel() async { await LabelLaws.outputLabelIgnoresTheModel(.kernel) }

    @Test(.shrinking(false)) func outputLabelCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("label is the join of cited lines only") {
            await LabelLaws.outputLabelIgnoresTheModel(.labelFromCitedLinesOnly)
        }
    }

    @Test func onlyTheOwnerWidens() async { await LabelLaws.onlyTheOwnerWidens(.kernel) }

    @Test(.shrinking(false)) func onlyTheOwnerWidensCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("a release by the owner of another source is accepted") {
            await LabelLaws.onlyTheOwnerWidens(.releaseByAnyOwnerInLabel)
        }
    }

    @Test func unknownGivesNobody() async { await LabelLaws.unknownGivesNobody(.kernel) }

    @Test(.shrinking(false)) func unknownGivesNobodyCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("a missing grant reads as the whole roster") {
            await LabelLaws.unknownGivesNobody(.missingGrantReadsAsWholeRoster)
        }
    }

    @Test func strangersChangeNothing() async { await LabelLaws.strangersChangeNothing(.kernel) }

    @Test(.shrinking(false)) func strangersChangeNothingCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("a grant counts whoever signed it") {
            await LabelLaws.strangersChangeNothing(.grantSignerIgnored)
        }
    }

    @Test func aPartNobodyReadsAbsorbsEveryJoin() async { await LabelLaws.aPartNobodyReadsAbsorbsEveryJoin(.kernel) }

    @Test(.shrinking(false)) func aPartNobodyReadsCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("a missing grant reads as the whole roster") {
            await LabelLaws.aPartNobodyReadsAbsorbsEveryJoin(.missingGrantReadsAsWholeRoster)
        }
    }

    @Test func aJoinNeverWidensEitherPart() async { await LabelLaws.aJoinNeverWidensEitherPart(.kernel) }

    @Test(.shrinking(false)) func aJoinNeverWidensCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("readers are the union over sources") {
            await LabelLaws.aJoinNeverWidensEitherPart(.readersUnionOverSources)
        }
    }
}
