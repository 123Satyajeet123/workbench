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
        #expect(throws: ReadError.notPermitted) {
            try WhatsAppChatReader.groups(container: fixture.container, policy: whatsappOn.policy)
        }
        #expect(throws: ReadError.storeMissing) {
            try WhatsAppChatReader.groups(
                container: fixture.container.appending(path: "absent"), policy: whatsappOn.policy)
        }
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
        let policy = CapturePolicy(switches: [.whatsapp: true])
        let chosen = try WhatsAppChatReader.chats(
            matching: ChatSelection(nameContains: "tea", directWithMembers: true), container: fixture.container,
            policy: policy)
        #expect(chosen.map(\.name) == ["Team", "Bharat K"])
        #expect(chosen.map(\.isGroup) == [true, false])
        let groupsOnly = try WhatsAppChatReader.chats(
            matching: ChatSelection(nameContains: "TEAM", directWithMembers: false), container: fixture.container,
            policy: policy)
        #expect(groupsOnly.map(\.name) == ["Team"])
        #expect(
            try WhatsAppChatReader.chats(
                matching: ChatSelection(nameContains: " ", directWithMembers: true), container: fixture.container,
                policy: policy
            ).isEmpty, "no words, no chats")
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
