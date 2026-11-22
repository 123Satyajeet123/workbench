import Testing

/// Each line identity law runs twice: it must hold on `Lines`, and it must fail on its planted break.
@Suite struct LineLawTests {
    @Test func sameInputsGiveTheSameID() async { await LineLaws.sameInputsGiveTheSameID(.lines) }

    @Test(.shrinking(false)) func sameInputsCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the read time is in the hash (research E-R2 §5 test 2)") {
            await LineLaws.sameInputsGiveTheSameID(.readTimeInHash)
        }
    }

    @Test func canonicalSpellingsGiveTheSameID() async { await LineLaws.canonicalSpellingsGiveTheSameID(.lines) }

    @Test(.shrinking(false)) func canonicalSpellingsCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the raw UTF-8 of the text is hashed (screenpipe defect 4)") {
            await LineLaws.canonicalSpellingsGiveTheSameID(.rawTextBytes)
        }
    }

    @Test func spacingAndInvisibleCharactersKeepTheID() async {
        await LineLaws.spacingAndInvisibleCharactersKeepTheID(.lines)
    }

    @Test(.shrinking(false)) func spacingAndInvisibleCharactersCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("NFC only: no white space fold, no invisible-character strip") {
            await LineLaws.spacingAndInvisibleCharactersKeepTheID(.nfcWithoutSpacingRules)
        }
    }

    @Test func anyChangeInTheEntityChangesTheID() async { await LineLaws.anyChangeInTheEntityChangesTheID(.lines) }

    @Test(.shrinking(false)) func anyChangeInTheEntityCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("entity fields joined with no length prefix") {
            await LineLaws.anyChangeInTheEntityChangesTheID(.concatenatedEntityFields)
        }
    }

    @Test func anyChangeInTheTextChangesTheID() async { await LineLaws.anyChangeInTheTextChangesTheID(.lines) }

    @Test(.shrinking(false)) func anyChangeInTheTextCatchesPlantedBreakCase() async {
        await expectPlantedBreakCaught("the text is lower-cased before hashing") {
            await LineLaws.anyChangeInTheTextChangesTheID(.lowercasesText)
        }
    }

    @Test(.shrinking(false)) func anyChangeInTheTextCatchesPlantedBreakJoiners() async {
        await expectPlantedBreakCaught("ZWJ and ZWNJ are stripped with the other zero-width characters") {
            await LineLaws.anyChangeInTheTextChangesTheID(.stripsJoiners)
        }
    }

    @Test func theReaderVersionNeverChangesTheID() async { await LineLaws.theReaderVersionNeverChangesTheID(.lines) }

    @Test(.shrinking(false)) func theReaderVersionCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the reader version is in the hash (screenpipe defect 3)") {
            await LineLaws.theReaderVersionNeverChangesTheID(.readerVersionInHash)
        }
    }

    @Test func identityTextIsNFCAndStable() async { await LineLaws.identityTextIsNFCAndStable(.lines) }

    @Test(.shrinking(false)) func identityTextCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("NFC runs before the invisible characters are removed") {
            await LineLaws.identityTextIsNFCAndStable(.normalizesBeforeStripping)
        }
    }

    @Test func duplicatesInOneReadStayDistinctAndStable() async {
        await LineLaws.duplicatesInOneReadStayDistinctAndStable(.lines)
    }

    @Test(.shrinking(false)) func duplicatesInOneReadCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("no duplicate ordinal: equal texts in one container merge") {
            await LineLaws.duplicatesInOneReadStayDistinctAndStable(.noDuplicateOrdinal)
        }
    }

    @Test func reorderedOrScrolledReadsMapOntoTheSameLines() async {
        await LineLaws.reorderedOrScrolledReadsMapOntoTheSameLines(.lines)
    }

    @Test(.shrinking(false)) func reorderedOrScrolledReadsCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the ordinal is the place in the read (screenpipe defect 2)") {
            await LineLaws.reorderedOrScrolledReadsMapOntoTheSameLines(.positionOrdinal)
        }
    }

    @Test func theInstantNotTheLocalTimeMakesTheID() async {
        await LineLaws.theInstantNotTheLocalTimeMakesTheID(.lines)
    }

    @Test(.shrinking(false)) func theInstantCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the occurrence is hashed as local wall time (screenpipe defect 1)") {
            await LineLaws.theInstantNotTheLocalTimeMakesTheID(.localWallTime)
        }
    }

    @Test func aViewIsItsLinesInOrder() async { await LineLaws.aViewIsItsLinesInOrder(.lines) }

    @Test(.shrinking(false)) func aViewCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the line ids are sorted before the view is hashed") {
            await LineLaws.aViewIsItsLinesInOrder(.sortedView)
        }
    }
}
