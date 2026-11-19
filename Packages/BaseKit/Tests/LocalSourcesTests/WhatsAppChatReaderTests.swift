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

    @Test func withoutWhatsAppsAddressBookPushNamesStandIn() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.run(
            """
            INSERT INTO ZWAGROUPMEMBER VALUES (10, 4, '111111111@lid', '', '', 1);
            INSERT INTO ZWAPROFILEPUSHNAME (ZJID, ZPUSHNAME) VALUES ('111111111@lid', 'Tattwa');
            """)
        #expect(try await reader(fixture, chat: groupJID).members().map(\.name) == ["Asha", "Bharat", "Tattwa"])
    }
}
