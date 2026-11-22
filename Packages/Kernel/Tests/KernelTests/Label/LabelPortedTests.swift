import Kernel
import Testing

/// Cases ported from qm `test/memory-disclosure.test.ts` (7689355c2fad) and agentes-chat `packages/engine/test/`
/// (fa9288114e82), as listed in research K5 §9.1. Each runs on the kernel and on a planted break it must catch.
/// The OpenAPPA cases (`label.rs:1214, 1252`) are properties in `LabelLaws`. Not ported, with the reason:
/// qm 76-89 needs release rules over classes (ADR-010); qm 203-219, 221-229, 326-346 and agentes-chat
/// `memory.test.ts:479-519` test edits, search and link expansion, which belong to the store; the kernel part of
/// 479-519 is the same check as 431-477.
enum PortedCases {
    static let roster = Team.roster
    static let grants = Team.grants

    /// qm 91-101: copying a private fact into a readable notebook does not make its audience eligible.
    static func aCopyIntoTheGroupKeepsItsOwnAudience(_ labels: LabelAlgebra) {
        let copied = labels.join(Label(source: Team.foundersGroup), Label(source: Team.founderScreen))
        #expect(!labels.admits(copied, [Team.founder, Team.shivansh], grants, roster))
        #expect(labels.admits(copied, [Team.founder], grants, roster))
        let isolated = Grant(signer: Team.founder, source: Team.founderScreenSource, readers: [], epoch: 2)
        #expect(!labels.admits(copied, [Team.founder], grants + [isolated], roster))
    }

    /// qm 103-114: the owner's own copy rechecks the original source's membership.
    static func aCopyDisappearsForAReaderTheSourceDropped(_ labels: LabelAlgebra) {
        let notes = source(Team.dev, "notes")
        let copy = labels.join(Label(source: Team.partnerships), Label(source: notes.id))
        let devNotes = Grant(signer: Team.dev, source: notes, readers: [Team.dev], epoch: 1)
        #expect(labels.readers(copy, grants + [devNotes], roster) == [Team.dev])
        let revoked = Grant(signer: Team.aditya, source: Team.partnershipsSource, readers: [Team.aditya], epoch: 2)
        #expect(labels.readers(copy, grants + [devNotes, revoked], roster).isEmpty)
    }

    /// qm 141-157: an empty audience and failed lookups fail closed.
    static func anEmptyAudienceAndAMissingOrDisputedGrantFailClosed(_ labels: LabelAlgebra) {
        let fact = Label(source: Team.foundersGroup)
        #expect(!labels.admits(fact, [], grants, roster))
        #expect(labels.readers(fact, [], roster).isEmpty)
        let rival = Grant(signer: Team.founder, source: Team.foundersGroupSource, readers: [Team.dev], epoch: 1)
        #expect(labels.readers(fact, grants + [rival], roster).isEmpty)
    }

    /// qm 159-164: every source is required, not only the notebook owner's.
    static func everySourceIsRequired(_ labels: LabelAlgebra) {
        let merged = labels.join(Label(source: Team.foundersGroup), Label(source: Team.partnerships))
        #expect(labels.readers(merged, grants, roster) == [Team.aditya])
    }

    /// qm 183-194: the destination's current members decide on every read, not the audience taken earlier.
    static func theDestinationsCurrentMembersDecide(_ labels: LabelAlgebra) {
        let fact = Label(source: Team.partnerships)
        #expect(labels.admits(fact, [Team.aditya], grants, roster))
        #expect(!labels.admits(fact, [Team.aditya, Team.founder], grants, roster))
    }

    /// qm 196-201: an unknown destination roster cannot authorize a disclosure.
    static func anEmptyRosterAuthorizesNobody(_ labels: LabelAlgebra) {
        let fact = Label(source: Team.foundersGroup)
        #expect(labels.readers(fact, grants, Roster(members: [])).isEmpty)
        #expect(!labels.admits(fact, [Team.founder], grants, Roster(members: [])))
    }

    /// qm 265-280: decisions are never cached across reads; a newer grant counts at the next read.
    static func aNewerGrantCountsAtTheNextRead(_ labels: LabelAlgebra) {
        let fact = Label(source: Team.foundersGroup)
        #expect(labels.readers(fact, grants, roster).count == 3)
        let narrowed = Grant(signer: Team.founder, source: Team.foundersGroupSource, readers: [Team.founder], epoch: 2)
        #expect(labels.readers(fact, grants + [narrowed], roster) == [Team.founder])
    }

    /// qm 282-304: an audience with an unresolved member is refused whole, not trimmed.
    static func anAudienceWithAnUnresolvedMemberIsRefusedWhole(_ labels: LabelAlgebra) {
        let fact = Label(source: Team.foundersGroup)
        #expect(!labels.admits(fact, [Team.founder, person("unresolved")], grants, roster))
        #expect(labels.admits(fact, [Team.founder], grants, roster))
    }

    /// agentes-chat `memory.test.ts:431-477`: an item learned in a private channel is shown in that channel and
    /// never in another one. A channel shows an item only when all its members may read it.
    static func aPrivateChannelsItemStaysInThatChannel(_ labels: LabelAlgebra) {
        let general = source(Team.founder, "chat:general")
        let secret = source(Team.founder, "chat:secret")
        let channelGrants = [
            Grant(signer: Team.founder, source: general, readers: Set(Team.everyone), epoch: 1),
            Grant(signer: Team.founder, source: secret, readers: [Team.founder, Team.aditya], epoch: 1),
        ]
        let generalMembers = Set(Team.everyone)
        let secretMembers: Set = [Team.founder, Team.aditya]
        let acquisition = Label(source: secret.id)
        #expect(!labels.admits(acquisition, generalMembers, channelGrants, roster))
        #expect(labels.admits(acquisition, secretMembers, channelGrants, roster))
        #expect(labels.admits(Label(source: general.id), generalMembers, channelGrants, roster))
    }

    /// agentes-chat `memory-team.test.ts:164-192`, inverted: a reviewer may not make an item team-wide; the owner may.
    static func aReviewerCannotOpenAnItemOnlyTheOwnerCan(_ labels: LabelAlgebra) {
        let teamWide = source(Team.aditya, "release:team")
        let all = grants + [Grant(signer: Team.aditya, source: teamWide, readers: roster.members, epoch: 1)]
        let item = Label(source: Team.partnerships)
        #expect(
            labels.release(item, Release(signer: Team.founder, covers: Team.partnerships, to: teamWide.id), all) == nil)
        let opened = labels.release(item, Release(signer: Team.aditya, covers: Team.partnerships, to: teamWide.id), all)
        #expect(opened.map { labels.readers($0, all, roster) } == roster.members)
    }

    /// agentes-chat `packages/db/src/schema/context.ts:33-34`, inverted: no channel never means the whole org; a
    /// source nobody granted reads as nobody.
    static func noSourcesNeverMeansEveryone(_ labels: LabelAlgebra) {
        #expect(throws: LabelError.noSources) { try Label(sources: [], classes: []) }
        let ungranted = Label(source: source(Team.founder, "chat:new").id)
        #expect(labels.readers(ungranted, grants, roster).isEmpty)
    }
}

@Suite struct LabelPortedTests {
    @Test func qm91() { PortedCases.aCopyIntoTheGroupKeepsItsOwnAudience(.kernel) }
    @Test func qm91CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("readers are the union over sources") {
            PortedCases.aCopyIntoTheGroupKeepsItsOwnAudience(.readersUnionOverSources)
        }
    }

    @Test func qm103() { PortedCases.aCopyDisappearsForAReaderTheSourceDropped(.kernel) }
    @Test func qm103CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("readers use the oldest grant") {
            PortedCases.aCopyDisappearsForAReaderTheSourceDropped(.readersUseOldestGrant)
        }
    }

    @Test func qm141() { PortedCases.anEmptyAudienceAndAMissingOrDisputedGrantFailClosed(.kernel) }
    @Test func qm141CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("a missing grant reads as the whole roster") {
            PortedCases.anEmptyAudienceAndAMissingOrDisputedGrantFailClosed(.missingGrantReadsAsWholeRoster)
        }
    }

    @Test func qm159() { PortedCases.everySourceIsRequired(.kernel) }
    @Test func qm159CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("readers are the union over sources") {
            PortedCases.everySourceIsRequired(.readersUnionOverSources)
        }
    }

    @Test func qm183() { PortedCases.theDestinationsCurrentMembersDecide(.kernel) }
    @Test func qm183CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the audience is trimmed to its readers") {
            PortedCases.theDestinationsCurrentMembersDecide(.admitsTrimsTheAudience)
        }
    }

    @Test func qm196() { PortedCases.anEmptyRosterAuthorizesNobody(.kernel) }
    @Test func qm196CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("readers ignore the roster") {
            PortedCases.anEmptyRosterAuthorizesNobody(.readersIgnoreRoster)
        }
    }

    @Test func qm265() { PortedCases.aNewerGrantCountsAtTheNextRead(.kernel) }
    @Test func qm265CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("readers use the oldest grant") {
            PortedCases.aNewerGrantCountsAtTheNextRead(.readersUseOldestGrant)
        }
    }

    @Test func qm282() { PortedCases.anAudienceWithAnUnresolvedMemberIsRefusedWhole(.kernel) }
    @Test func qm282CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the audience is trimmed to its readers") {
            PortedCases.anAudienceWithAnUnresolvedMemberIsRefusedWhole(.admitsTrimsTheAudience)
        }
    }

    @Test func agentesChat431() { PortedCases.aPrivateChannelsItemStaysInThatChannel(.kernel) }
    @Test func agentesChat431CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("the audience is trimmed to its readers") {
            PortedCases.aPrivateChannelsItemStaysInThatChannel(.admitsTrimsTheAudience)
        }
    }

    @Test func agentesChatTeam164() { PortedCases.aReviewerCannotOpenAnItemOnlyTheOwnerCan(.kernel) }
    @Test func agentesChatTeam164CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("anyone with the reviewer role may open an item") {
            PortedCases.aReviewerCannotOpenAnItemOnlyTheOwnerCan(.releaseBySomeoneWithTheRole)
        }
    }

    @Test func agentesChatContext33() { PortedCases.noSourcesNeverMeansEveryone(.kernel) }
    @Test func agentesChatContext33CatchesPlantedBreak() async {
        await expectPlantedBreakCaught("a missing grant reads as the whole roster") {
            PortedCases.noSourcesNeverMeansEveryone(.missingGrantReadsAsWholeRoster)
        }
    }
}
