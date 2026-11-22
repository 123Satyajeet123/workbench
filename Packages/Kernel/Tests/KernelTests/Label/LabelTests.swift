import Kernel
import Testing

/// The team of research 47 §3, and the guards of `Label`, `Grants` and `Release`, each tested both ways.
enum Team {
    static let founder = person("founder")
    static let shivansh = person("shivansh")
    static let aditya = person("aditya")
    static let dev = person("dev")
    static let everyone = [founder, shivansh, aditya, dev]

    static let foundersGroupSource = source(founder, "wa:founders")
    static let founderScreenSource = source(founder, "screen")
    static let partnershipsSource = source(aditya, "wa:partnerships")
    static let financeSource = source(aditya, "release:finance")

    static let foundersGroup = foundersGroupSource.id
    static let founderScreen = founderScreenSource.id
    static let partnerships = partnershipsSource.id
    static let finance = financeSource.id

    static let roster = Roster(members: Set(everyone))
    static let grants = [
        Grant(signer: founder, source: foundersGroupSource, readers: [founder, shivansh, aditya], epoch: 1),
        Grant(signer: founder, source: founderScreenSource, readers: [founder], epoch: 1),
        Grant(signer: aditya, source: partnershipsSource, readers: [aditya, dev], epoch: 1),
        Grant(signer: aditya, source: financeSource, readers: [aditya, founder], epoch: 1),
    ]
}

@Suite struct LabelTests {
    @Test func aLabelNeedsAtLeastOneSource() throws {
        #expect(throws: LabelError.noSources) { try Label(sources: [], classes: [sourceClass("personal")]) }
        let label = try Label(sources: [Team.foundersGroup], classes: [])
        #expect(label.sources == [Team.foundersGroup])
    }

    @Test func joinUnitesSourcesAndClasses() {
        let group = Label(source: Team.foundersGroup, classes: [sourceClass("chat")])
        let screen = Label(source: Team.founderScreen, classes: [sourceClass("personal")])
        let joined = group.joined(with: screen)
        #expect(joined.sources == [Team.foundersGroup, Team.founderScreen])
        #expect(joined.classes == [sourceClass("chat"), sourceClass("personal")])
        #expect(group.joined(with: [screen, group]) == joined)
        #expect(group.joined(with: []) == group)
    }

    @Test func s1AFactFromTheFoundersGroupReachesTheThreeFounders() {
        let fact = Label(source: Team.foundersGroup)
        let readers = fact.readers(grants: Grants(Team.grants), roster: Team.roster)
        #expect(readers == [Team.founder, Team.shivansh, Team.aditya])
    }

    @Test func s2ASummaryOverTheGroupAndThePrivateScreenReachesOnlyTheFounder() {
        let summary = Label(source: Team.foundersGroup).joined(with: Label(source: Team.founderScreen))
        #expect(summary.readers(grants: Grants(Team.grants), roster: Team.roster) == [Team.founder])
    }

    @Test func aSourceIdIsDerivedFromItsOwnerAndKey() {
        #expect(source(Team.founder, "wa:founders").id == Team.foundersGroup)
        #expect(source(Team.dev, "wa:founders").id != Team.foundersGroup)
        #expect(source(Team.founder, "wa:founders2").id != Team.foundersGroup)
    }

    @Test func theNewestEpochDecidesAndOlderOnesDoNot() {
        let narrowed = Grant(signer: Team.founder, source: Team.foundersGroupSource, readers: [Team.founder], epoch: 2)
        #expect(Grants(Team.grants + [narrowed]).current(for: Team.foundersGroup) == narrowed)
        let older = Grant(signer: Team.founder, source: Team.foundersGroupSource, readers: [Team.dev], epoch: 0)
        #expect(Grants(Team.grants + [older]).current(for: Team.foundersGroup)?.epoch == 1)
    }

    @Test func twoOwnerGrantsAtOneEpochCountOnlyWhenTheyAgree() {
        let copy = Team.grants[0]
        let agreeing = Grants(Team.grants + [copy])
        #expect(agreeing.current(for: Team.foundersGroup) == copy)
        #expect(agreeing.conflicted.isEmpty)
        let rival = Grant(signer: Team.founder, source: Team.foundersGroupSource, readers: [Team.dev], epoch: 1)
        let disputed = Grants(Team.grants + [rival])
        #expect(disputed.current(for: Team.foundersGroup) == nil)
        #expect(disputed.conflicted == [Team.foundersGroup])
    }

    /// Review 1 F4: a grant signed by someone other than the owner is refused and counted, and never blocks the
    /// owner's grant, however new it is.
    @Test func aGrantNotSignedByTheOwnerIsRefusedAndBlocksNothing() {
        let claim = Grant(signer: Team.dev, source: Team.foundersGroupSource, readers: [Team.dev], epoch: 7)
        let withClaim = Grants(Team.grants + [claim])
        #expect(withClaim.refused == [claim])
        #expect(withClaim.current(for: Team.foundersGroup) == Team.grants[0])
        let clean = Grants(Team.grants)
        #expect(clean.refused.isEmpty)
        #expect(clean.current(for: Team.foundersGroup)?.signer == Team.founder)
    }

    @Test func anAudienceIsAdmittedOnlyWhenItIsNonEmptyAndEveryoneInItReads() {
        let fact = Label(source: Team.foundersGroup)
        let grants = Grants(Team.grants)
        #expect(fact.admits([Team.shivansh, Team.aditya], grants: grants, roster: Team.roster))
        #expect(!fact.admits([Team.shivansh, Team.dev], grants: grants, roster: Team.roster))
        #expect(!fact.admits([], grants: grants, roster: Team.roster))
    }
}

@Suite struct ReleaseTests {
    private let deal = Label(source: Team.partnerships, classes: [sourceClass("money")])
    private let grants = Grants(Team.grants)

    @Test func s3TheOwnersReleaseOpensTheFieldsToFinance() throws {
        let release = Release(signer: Team.aditya, covers: Team.partnerships, to: Team.finance)
        let released = try deal.released(by: release, grants: grants)
        #expect(released.sources == [Team.finance])
        #expect(released.classes == deal.classes)
        #expect(released.readers(grants: grants, roster: Team.roster) == [Team.aditya, Team.founder])
        #expect(deal.readers(grants: grants, roster: Team.roster) == [Team.aditya, Team.dev])
    }

    @Test func aReleaseBySomeoneOtherThanTheOwnerIsRefused() {
        let byFounder = Release(signer: Team.founder, covers: Team.partnerships, to: Team.finance)
        #expect(throws: ReleaseError.signerIsNotOwner) { try deal.released(by: byFounder, grants: grants) }
    }

    @Test func aReleaseToASourceTheSignerDoesNotOwnIsRefused() {
        let intoFoundersGroup = Release(signer: Team.aditya, covers: Team.partnerships, to: Team.foundersGroup)
        #expect(throws: ReleaseError.targetNotOwnedBySigner) {
            try deal.released(by: intoFoundersGroup, grants: grants)
        }
        let ungranted = source(Team.aditya, "release:nobody").id
        let unknownTarget = Release(signer: Team.aditya, covers: Team.partnerships, to: ungranted)
        #expect(throws: ReleaseError.targetNotOwnedBySigner) { try deal.released(by: unknownTarget, grants: grants) }
    }

    @Test func aReleaseCoversOnlyASourceInTheLabel() {
        let release = Release(signer: Team.founder, covers: Team.founderScreen, to: Team.finance)
        #expect(throws: ReleaseError.sourceNotInLabel) { try deal.released(by: release, grants: grants) }
    }

    @Test func aReleaseOfASourceWithNoCurrentGrantIsRefused() {
        let ungranted = source(Team.aditya, "wa:unknown").id
        let label = Label(source: ungranted)
        let release = Release(signer: Team.aditya, covers: ungranted, to: Team.finance)
        #expect(throws: ReleaseError.noCurrentGrant) { try label.released(by: release, grants: grants) }
    }

    @Test func oneOwnersReleaseLeavesTheOtherOwnersPartInPlace() throws {
        let summary = deal.joined(with: Label(source: Team.foundersGroup))
        let release = Release(signer: Team.aditya, covers: Team.partnerships, to: Team.finance)
        let released = try summary.released(by: release, grants: grants)
        #expect(released.sources == [Team.finance, Team.foundersGroup])
        #expect(released.readers(grants: grants, roster: Team.roster) == [Team.aditya, Team.founder])
    }
}
