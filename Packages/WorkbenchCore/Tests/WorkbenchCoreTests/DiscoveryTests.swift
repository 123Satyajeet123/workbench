import Foundation
import Lines
import Testing

@testable import WorkbenchCore

/// What every source says about its containers: one shape, one audience rule, one merge, one chooser rule.
@Suite struct DiscoveryTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let group = Container(id: "123-1@g.us", kind: .group, title: "Team Ops")
    static let friend = Container(id: "919800000002@s.whatsapp.net", kind: .direct, title: "Bharat")

    static func sighting(
        _ container: Container, by source: String = "store", at offset: TimeInterval = 0,
        members: [String]? = nil, proof: Membership.Proof = .sourceTable
    ) -> ContainerSighting {
        ContainerSighting(
            container: container, source: source, observedAt: now.addingTimeInterval(offset),
            membership: members.flatMap { Membership(members: $0, proof: proof) })
    }

    // MARK: membership and audience

    @Test func aMembershipHoldsEachIdOnceAndAnEmptyListProvesNothing() throws {
        let membership = try #require(Membership(members: ["b@lid", "a@lid", "b@lid", ""], proof: .infoPanel))
        #expect(membership.members == ["a@lid", "b@lid"])
        #expect(Membership(members: [] as [String], proof: .infoPanel) == nil)
        #expect(Membership(members: [""], proof: .sourceTable) == nil)
    }

    @Test func aGroupHasNoAudienceWithoutAMembershipAndADirectChatNeedsNone() throws {
        #expect(AudienceRule.digest(of: Self.group, owner: "me", membership: nil) == nil)
        let members = try #require(Membership(members: ["a@lid", "b@lid"], proof: .infoPanel))
        #expect(
            AudienceRule.digest(of: Self.group, owner: "me", membership: members)
                == AudienceDigest(owner: "me", members: ["a@lid", "b@lid"]))
        #expect(
            AudienceRule.digest(of: Self.friend, owner: "me", membership: nil)
                == AudienceDigest(owner: "me", members: [Self.friend.id]))
    }

    // MARK: merge

    @Test func twoSourcesThatSeeOneChatGiveOneCandidateWithBothSources() {
        let merged = ContainerCandidates.merge([
            Self.sighting(Self.group, by: "store"), Self.sighting(Self.friend, by: "store"),
            Self.sighting(Self.group, by: "web"),
        ])
        #expect(merged.map(\.id) == [Self.group.id, Self.friend.id])
        #expect(merged[0].seenBy == ["store", "web"])
        #expect(merged[1].seenBy == ["store"])
    }

    @Test func theTitleIsTheFirstOneThatIsNotEmptyAndTheMembershipIsTheNewest() throws {
        let untitled = Container(id: Self.group.id, kind: .group, title: "")
        let merged = ContainerCandidates.merge([
            Self.sighting(untitled, by: "web", at: 0, members: ["old@lid"], proof: .infoPanel),
            Self.sighting(Self.group, by: "store", at: 10, members: ["new@lid"]),
            Self.sighting(Self.group, by: "web", at: 5, members: ["middle@lid"], proof: .infoPanel),
        ])
        #expect(merged.count == 1)
        #expect(merged[0].container.title == "Team Ops")
        #expect(merged[0].membership?.members == ["new@lid"])
    }

    // MARK: the chooser rule over merged candidates

    @Test func theRulesWorkOverCandidatesFromEverySource() {
        let other = Container(id: "123-2@g.us", kind: .group, title: "Family")
        let stranger = Container(id: "919800000003@s.whatsapp.net", kind: .direct, title: "Stranger")
        let merged = ContainerCandidates.merge([
            Self.sighting(Self.friend, by: "store"), Self.sighting(stranger, by: "store"),
            Self.sighting(other, by: "store", members: [Self.friend.id]),
            Self.sighting(Self.group, by: "web", members: [Self.friend.id], proof: .infoPanel),
        ])
        let withDirect = ChatSelection(nameContains: "ops", directWithMembers: true).choose(from: merged)
        #expect(
            withDirect.map(\.id) == [Self.group.id, Self.friend.id],
            "the group came from the page, the chat from the store")
        #expect(
            ChatSelection(nameContains: "OPS", directWithMembers: false).choose(from: merged).map(\.id) == [
                Self.group.id
            ])
        #expect(
            ChatSelection(nameContains: " ", directWithMembers: true).choose(from: merged).isEmpty, "no words, no chats"
        )
        #expect(ChatSelection(nameContains: "zzz", directWithMembers: true).choose(from: merged).isEmpty)
    }

    @Test func aGroupWhoseMembersAreNotKnownPullsInNoDirectChat() {
        let merged = ContainerCandidates.merge([Self.sighting(Self.friend), Self.sighting(Self.group)])
        #expect(
            ChatSelection(nameContains: "ops", directWithMembers: true).choose(from: merged).map(\.id) == [
                Self.group.id
            ])
    }

    // MARK: the board

    private func board() -> SightingBoard { SightingBoard(descriptor: .whatsAppWeb) }

    private static let policyOn = CapturePolicy(switches: [.whatsapp: true])

    @Test func theBoardKeepsASightingOnlyWhileTheWindowIsOpenAndForgetsAllWhenItCloses() {
        let board = board()
        #expect(board.record(Self.sighting(Self.group, by: "web")) == false)
        #expect(board.sightings(policy: Self.policyOn, now: Self.now).isEmpty)
        board.open()
        #expect(board.record(Self.sighting(Self.group, by: "web")))
        #expect(board.sightings(policy: Self.policyOn, now: Self.now).map(\.container.id) == [Self.group.id])
        board.close()
        #expect(board.sightings(policy: Self.policyOn, now: Self.now).isEmpty)
        #expect(board.isOpen == false)
    }

    @Test func theBoardGivesNothingWhileTheConsentSwitchIsOff() {
        let board = board()
        board.open()
        board.record(Self.sighting(Self.group, by: "web"))
        #expect(board.sightings(policy: CapturePolicy(), now: Self.now).isEmpty)
    }

    @Test func forgettingAChatDropsItsSightingItsMembersAndItsNote() {
        let board = board()
        board.open()
        board.record(Self.sighting(Self.group, by: "web", members: ["a@lid"], proof: .infoPanel))
        board.record(Self.sighting(Self.friend, by: "web"))
        board.wait(on: Self.group.id, words: "Open the group info.")
        board.forget(Self.group.id)
        let left = board.sightings(policy: Self.policyOn, now: Self.now)
        #expect(left.map(\.container.id) == [Self.friend.id])
        #expect(board.waiting(on: Self.group.id) == nil)
    }

    @Test func aNewSightingOfAChatReplacesTheOldOne() {
        let board = board()
        board.open()
        board.record(Self.sighting(Self.group, by: "web", at: 0))
        board.record(Self.sighting(Self.group, by: "web", at: 9, members: ["a@lid"], proof: .infoPanel))
        let kept = board.sightings(policy: Self.policyOn, now: Self.now)
        #expect(kept.count == 1 && kept[0].membership?.members == ["a@lid"])
    }
}
