import Foundation
import Lines
import Testing
import WorkbenchCore

@testable import LocalSources

/// The WhatsApp store as a container source: the chats and groups it holds, and the active members of each group, as ids.
@Suite struct WhatsAppDiscoveryTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func reader(_ fixture: WhatsAppFixture) -> WhatsAppChatReader {
        WhatsAppChatReader(container: fixture.container, chatJIDs: [], policy: whatsappOn)
    }

    @Test func theStoreListsItsChatsAndGroupsByIdKindAndTitleNewestFirst() throws {
        let fixture = try WhatsAppFixture()
        let seen = try reader(fixture).sightings(policy: whatsappOn.policy, now: now)
        #expect(seen.map(\.container.title) == ["Team", "Family", "Friend", "Me"])
        #expect(seen.map(\.container.kind) == [.group, .group, .direct, .direct])
        #expect(seen.map(\.container.id) == [groupJID, otherGroupJID, otherJID, selfJID])
        #expect(seen.allSatisfy { $0.source == SourceDescriptor.whatsAppChat.key && $0.observedAt == now })
    }

    @Test func aGroupCarriesItsActiveMembersByIdAndADirectChatCarriesNone() throws {
        let fixture = try WhatsAppFixture()
        let seen = try reader(fixture).sightings(policy: whatsappOn.policy, now: now)
        let team = try #require(seen.first { $0.container.id == groupJID }?.membership)
        #expect(team.members == ["a@s.whatsapp.net", "b@s.whatsapp.net"], "c left the group")
        #expect(team.proof == .sourceTable)
        #expect(seen.first { $0.container.id == otherJID }?.membership == nil)
    }

    @Test func aGroupWithNoActiveMemberHasNoMembership() throws {
        let fixture = try WhatsAppFixture()
        try fixture.run("UPDATE ZWAGROUPMEMBER SET ZISACTIVE = 0 WHERE ZCHATSESSION = 5")
        let seen = try reader(fixture).sightings(policy: whatsappOn.policy, now: now)
        #expect(seen.first { $0.container.id == otherGroupJID }?.membership == nil)
    }

    @Test func listingNeedsCaptureAndTheWhatsAppSwitchOn() throws {
        let fixture = try WhatsAppFixture()
        #expect(throws: ReadError.denied(.sourceSwitchedOff)) {
            try reader(fixture).sightings(policy: CapturePolicy(), now: now)
        }
        #expect(throws: ReadError.denied(.captureOff)) {
            try reader(fixture).sightings(policy: CapturePolicy(mode: .off, switches: [.whatsapp: true]), now: now)
        }
    }

    @Test func aStoreTheSystemWillNotOpenOrAMissingOneIsReportedNotListed() throws {
        let fixture = try WhatsAppFixture()
        let file = fixture.container.appending(path: "ChatStorage.sqlite").path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file) }
        #expect(throws: ReadError.notPermitted) { try reader(fixture).sightings(policy: whatsappOn.policy, now: now) }
        let absent = WhatsAppChatReader(
            container: fixture.container.appending(path: "absent"), chatJIDs: [], policy: whatsappOn)
        #expect(throws: ReadError.storeMissing) { try absent.sightings(policy: whatsappOn.policy, now: now) }
    }

    @Test func theStoreAudienceFollowsTheOneRule() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.run("DELETE FROM ZWAGROUPMEMBER WHERE ZCHATSESSION = 5")
        let seen = try reader(fixture).sightings(policy: whatsappOn.policy, now: now)
        let family = try #require(seen.first { $0.container.id == otherGroupJID })
        #expect(AudienceRule.digest(of: family.container, owner: "me", membership: family.membership) == nil)
        let team = try #require(seen.first { $0.container.id == groupJID })
        #expect(
            AudienceRule.digest(of: team.container, owner: "me", membership: team.membership)
                == AudienceDigest(owner: "me", members: ["a@s.whatsapp.net", "b@s.whatsapp.net"]))
    }
}
