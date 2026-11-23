import Foundation
import Testing
import WorkbenchCore

@testable import LocalSources

@Suite struct WhatsAppChatReaderTests {
    private func reader(_ fixture: WhatsAppFixture, chat: String = selfJID, policy: FixedPolicy = whatsappOn)
        -> WhatsAppChatReader
    {
        WhatsAppChatReader(container: fixture.container, chatJID: chat, policy: policy)
    }

    @Test func aStoreTheSystemWillNotOpenAsksForAccessAndAMissingOneAsksForTheApp() throws {
        let fixture = try WhatsAppFixture()
        let store = fixture.container.appending(path: "ChatStorage.sqlite").path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: store)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store) }
        #expect(ReadError.notPermitted.localizedDescription.contains("Full Disk Access"))
    }

    /// The founder's group (measured 2026-11-19): every member kept by a privacy ID with empty contact names, one
    /// "first name" holding encoded data, so every sender came out blank and Pip found no one's update.
    @Test func membersKeptByPrivacyIDGetTheNameTheFounderKnowsAndMentionsUseIt() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.run(
            """
            INSERT INTO ZWAGROUPMEMBER VALUES (10, 4, '111111111@lid', '', '+CgAQoZ741gY=', 1),
                (11, 4, '222222222@lid', '', '', 1), (12, 4, '333333333@lid', '', '', 1),
                (13, 4, '444444444@lid', '', '', 1);
            INSERT INTO ZWAPROFILEPUSHNAME (ZJID, ZPUSHNAME) VALUES ('111111111@lid', 'Push only'),
                ('222222222@lid', 'Bishal Singh');
            """)
        try fixture.contacts([("111111111@lid", "Rahul Sharma"), ("444444444@lid", "Bishal Singh")])
        try fixture.message(chat: 4, type: 0, text: "@333333333 build bhejo, @99999999 bhi", member: 10)
        let group = reader(fixture, chat: groupJID)
        let people = try await group.people()
        #expect(
            people.members.map(\.name) == [
                "Asha", "Bharat", "Bishal Singh ·2222", "Bishal Singh ·4444", "Member ·3333", "Rahul Sharma",
            ])
        #expect(people.names["111111111@lid"] == "Rahul Sharma")
        #expect(
            MemberNames.mentions(in: "@333333333 build bhejo, @99999999 bhi", names: people.names)
                == "@Member ·3333 build bhejo, @99999999 bhi")
    }

    @Test func aTagOfTheFounderByNumberOrPrivacyIDNamesTheFounder() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.run("INSERT INTO ZWAGROUPMEMBER VALUES (10, 4, '111111111@lid', 'Rahul', '', 1);")
        try fixture.own(phone: "919000000001@s.whatsapp.net", lid: "555555555@lid")
        let group = WhatsAppChatReader(
            container: fixture.container, chatJID: groupJID, policy: whatsappOn, me: "Kabir (You)")
        let people = try await group.people()
        #expect(
            MemberNames.mentions(in: "@555555555 approve karo, @919000000001 bhi, @111111111", names: people.names)
                == "@Kabir (You) approve karo, @Kabir (You) bhi, @Rahul")
    }

    @Test func theFounderIsNotOneOfTheGroupsMembers() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.run(
            """
            INSERT INTO ZWAGROUPMEMBER VALUES (10, 4, '555555555@lid', 'Kabir Rao', '', 1),
                (11, 4, '919000000001@s.whatsapp.net', 'Kabir Rao', '', 0), (12, 4, '666666666@lid', 'Kabir Rao', '', 1);
            """)
        try fixture.own(phone: "919000000001@s.whatsapp.net", lid: "555555555@lid")
        #expect(
            try await reader(fixture, chat: groupJID).people().members.map(\.name) == ["Asha", "Bharat", "Kabir Rao"])
    }

    @Test func withoutWhatsAppsAddressBookPushNamesStandIn() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.run(
            """
            INSERT INTO ZWAGROUPMEMBER VALUES (10, 4, '111111111@lid', '', '', 1);
            INSERT INTO ZWAPROFILEPUSHNAME (ZJID, ZPUSHNAME) VALUES ('111111111@lid', 'Tattwa');
            """)
        #expect(
            try await reader(fixture, chat: groupJID).people().members.map(\.name) == ["Asha", "Bharat", "Tattwa"])
    }

    /// The founder's rule (2026-11-19): every group with "Brave" in its name, and direct chats with people in them.
    @Test func aSelectionTakesMatchingGroupsAndDirectChatsWithTheirMembersOnly() throws {
        let fixture = try WhatsAppFixture()
        try fixture.run(
            """
            INSERT INTO ZWACHATSESSION VALUES (6, 'b@s.whatsapp.net', 0, 'Bharat K', 60),
                (7, 'z@s.whatsapp.net', 0, 'Stranger', 70);
            """)
        let candidates = ContainerCandidates.merge(
            try reader(fixture).sightings(policy: whatsappOn.policy, now: .now))
        let chosen = ChatSelection(nameContains: "tea", directWithMembers: true).choose(from: candidates)
        #expect(chosen.map(\.container.title) == ["Team", "Bharat K"])
        #expect(chosen.map(\.container.kind) == [.group, .direct])
        #expect(
            ChatSelection(nameContains: "TEAM", directWithMembers: false).choose(from: candidates)
                .map(\.container.title) == ["Team"])
        #expect(
            ChatSelection(nameContains: " ", directWithMembers: true).choose(from: candidates).isEmpty,
            "no words, no chats")
    }

    @Test func onePeopleReadCoversAGroupAndADirectChatAndNamesEachPersonOnce() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.run(
            """
            INSERT INTO ZWACHATSESSION VALUES (6, 'b@s.whatsapp.net', 0, 'Bharat K', 60);
            INSERT INTO ZWAGROUPMEMBER VALUES (5, 4, 'd@s.whatsapp.net', 'Dad', NULL, 0);
            """)
        let policy = FixedPolicy(
            policy: CapturePolicy(
                switches: [.whatsapp: true], allowList: [.whatsapp: [groupJID, otherGroupJID, "b@s.whatsapp.net"]]))
        let reader = WhatsAppChatReader(
            container: fixture.container, chatJIDs: [groupJID, otherGroupJID, "b@s.whatsapp.net"], policy: policy)
        let people = try await reader.people()
        let members = people.members
        #expect(people.names["b@s.whatsapp.net"] == "Bharat", "the other person of a direct chat, named")
        #expect(people.names[groupJID] == nil, "a group is no person")
        #expect(members.map(\.name) == ["Asha", "Bharat", "Dad"], "Dad is in two groups, once, without a suffix")
        #expect(members.first { $0.name == "Dad" }?.chats == [otherGroupJID], "Dad left the first group")
        #expect(members.first { $0.name == "Bharat" }?.chats?.contains("b@s.whatsapp.net") == true)
        await #expect(throws: (any Error).self, "every chat must be allowed") {
            _ = try await WhatsAppChatReader(
                container: fixture.container, chatJIDs: [groupJID, "z@s.whatsapp.net"], policy: policy
            ).people()
        }
    }
}

@Suite struct MemberNameTests {
    @Test func aNameWithNoLetterOrDigitNamesNobodyAndFallsBackToTheIDsEnd() {
        let names = MemberNames.resolve([
            (jid: "911111111111@s.whatsapp.net", candidates: [".", "Asha"]),
            (jid: "912222222222@s.whatsapp.net", candidates: ["🙂", "  "]),
            (jid: "913333333333@s.whatsapp.net", candidates: ["R2"]),
            (jid: "914444444444@s.whatsapp.net", candidates: ["अमित"]),
        ])
        #expect(names["911111111111@s.whatsapp.net"] == "Asha", "the next candidate with a letter")
        #expect(names["912222222222@s.whatsapp.net"] == "Member ·2222")
        #expect(names["913333333333@s.whatsapp.net"] == "R2")
        #expect(names["914444444444@s.whatsapp.net"] == "अमित", "letters of any script count")
    }
}
