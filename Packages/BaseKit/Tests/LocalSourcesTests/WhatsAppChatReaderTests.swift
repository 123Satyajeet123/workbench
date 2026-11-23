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

    @Test func aPathOutsideTheMessageFolderIsNotDownloaded() async throws {
        let fixture = try WhatsAppFixture()
        try Data("secret".utf8).write(to: fixture.container.appending(path: "outside.pdf"))
        try fixture.message(chat: 1, type: 8, text: nil, mediaPath: "../outside.pdf")
        #expect(try await reader(fixture).entries().first?.media == .notDownloaded)
    }

    @Test func entriesStayInsideTheAskedWindow() async throws {
        let fixture = try WhatsAppFixture()
        for (text, date) in [("before", 99.0), ("start", 100), ("inside", 150), ("end", 200)] {
            try fixture.message(chat: 4, type: 0, text: text, member: 1, date: date)
        }
        let entries = try await reader(fixture, chat: groupJID).entries(
            from: Date(timeIntervalSinceReferenceDate: 100), to: Date(timeIntervalSinceReferenceDate: 200))
        #expect(entries.map(\.text) == ["start", "inside"])
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
        #expect(
            try await group.members().map(\.name) == [
                "Asha", "Bharat", "Bishal Singh ·2222", "Bishal Singh ·4444", "Member ·3333", "Rahul Sharma",
            ])
        let entry = try #require(try await group.entries().first)
        #expect(entry.sender == .member(jid: "111111111@lid", name: "Rahul Sharma"))
        #expect(entry.text == "@Member ·3333 build bhejo, @99999999 bhi")
    }

    @Test func aTagOfTheFounderByNumberOrPrivacyIDNamesTheFounder() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.run("INSERT INTO ZWAGROUPMEMBER VALUES (10, 4, '111111111@lid', 'Rahul', '', 1);")
        try fixture.own(phone: "919000000001@s.whatsapp.net", lid: "555555555@lid")
        try fixture.message(
            chat: 4, type: 0, text: "@555555555 approve karo, @919000000001 bhi, @111111111", member: 10)
        let group = WhatsAppChatReader(
            container: fixture.container, chatJID: groupJID, policy: whatsappOn, me: "Kabir (You)")
        let entry = try #require(try await group.entries().first)
        #expect(entry.text == "@Kabir (You) approve karo, @Kabir (You) bhi, @Rahul")
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
            try await reader(fixture, chat: groupJID).members().map(\.name) == ["Asha", "Bharat", "Kabir Rao"])
    }

    @Test func withoutWhatsAppsAddressBookPushNamesStandIn() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.run(
            """
            INSERT INTO ZWAGROUPMEMBER VALUES (10, 4, '111111111@lid', '', '', 1);
            INSERT INTO ZWAPROFILEPUSHNAME (ZJID, ZPUSHNAME) VALUES ('111111111@lid', 'Tattwa');
            """)
        #expect(try await reader(fixture, chat: groupJID).members().map(\.name) == ["Asha", "Bharat", "Tattwa"])
    }

    @Test func everyChatIsEveryGroupAndDirectChatNewestFirst() throws {
        let fixture = try WhatsAppFixture()
        try fixture.run("INSERT INTO ZWACHATSESSION VALUES (6, 'z@s.whatsapp.net', 0, NULL, 5);")
        let every = try WhatsAppChatReader.everyChat(
            container: fixture.container, policy: CapturePolicy(switches: [.whatsapp: true]))
        #expect(every.map(\.name) == ["Team", "Family", "Friend", "Me", "z@s.whatsapp.net"])
        #expect(throws: ReadError.denied(.sourceSwitchedOff)) {
            try WhatsAppChatReader.everyChat(container: fixture.container, policy: CapturePolicy())
        }
    }

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

    @Test func oneReadCoversAGroupAndADirectChatAndNamesEachPersonOnce() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.run(
            """
            INSERT INTO ZWACHATSESSION VALUES (6, 'b@s.whatsapp.net', 0, 'Bharat K', 60);
            INSERT INTO ZWAGROUPMEMBER VALUES (5, 4, 'd@s.whatsapp.net', 'Dad', NULL, 0);
            """)
        try fixture.message(chat: 4, type: 0, text: "login done", member: 1, date: 100)
        try fixture.message(chat: 6, type: 0, text: "shipped the build", date: 110)
        try fixture.run("UPDATE ZWAMESSAGE SET ZISFROMME = 0 WHERE ZTEXT = 'shipped the build'")
        let policy = FixedPolicy(
            policy: CapturePolicy(
                switches: [.whatsapp: true], allowList: [.whatsapp: [groupJID, otherGroupJID, "b@s.whatsapp.net"]]))
        let reader = WhatsAppChatReader(
            container: fixture.container, chatJIDs: [groupJID, otherGroupJID, "b@s.whatsapp.net"], policy: policy)
        let (entries, members) = try await reader.read(from: .distantPast, to: .distantFuture)
        #expect(entries.map(\.chat) == [groupJID, "b@s.whatsapp.net"])
        #expect(entries.last?.sender == .member(jid: "b@s.whatsapp.net", name: "Bharat"), "the other person, named")
        try fixture.message(chat: 4, type: 0, text: "a notice", date: 120)
        try fixture.run("UPDATE ZWAMESSAGE SET ZISFROMME = 0 WHERE ZTEXT = 'a notice'")
        let notice = try #require(try await reader.entries().last)
        #expect(
            notice.sender != .member(jid: groupJID, name: MemberNames.fallback(for: groupJID)), "a group is no person")
        #expect(members.map(\.name) == ["Asha", "Bharat", "Dad"], "Dad is in two groups, once, without a suffix")
        #expect(members.first { $0.name == "Dad" }?.chats == [otherGroupJID], "Dad left the first group")
        #expect(members.first { $0.name == "Bharat" }?.chats?.contains("b@s.whatsapp.net") == true)
        await #expect(throws: (any Error).self, "every chat must be allowed") {
            _ = try await WhatsAppChatReader(
                container: fixture.container, chatJIDs: [groupJID, "z@s.whatsapp.net"], policy: policy
            ).read(from: .distantPast, to: .distantFuture)
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
