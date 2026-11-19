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

    @Test func readsOnlyTheNamedChat() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.message(chat: 1, type: 0, text: "pitch deck for Acme")
        try fixture.message(chat: 2, type: 0, text: "private chat with a friend")
        try fixture.message(chat: 2, type: 8, text: nil, mediaPath: "Media/friend.pdf")
        let entries = try await reader(fixture).entries()
        #expect(entries.map(\.text) == ["pitch deck for Acme"])
    }

    @Test func aStatusFeedWithTheSameIDIsNotRead() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.message(chat: 3, type: 0, text: "a status")
        #expect(try await reader(fixture).entries().isEmpty)
    }

    @Test func aDocumentGivesItsPathAndATitle() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.writeMedia("Media/deck.pdf")
        try fixture.message(chat: 1, type: 8, text: "see this", mediaPath: "Media/deck.pdf", title: "Acme deck")
        let entry = try #require(try await reader(fixture).entries().first)
        #expect(entry.kind == .document)
        #expect(entry.title == "Acme deck")
        #expect(entry.text == "see this")
        let expected = fixture.container.appending(path: "Message/Media/deck.pdf").resolvingSymlinksInPath()
        #expect(entry.media == .file(expected))
    }

    @Test func aVoiceNoteGivesItsPath() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.writeMedia("Media/note.opus")
        try fixture.message(chat: 1, type: 3, text: nil, mediaPath: "Media/note.opus")
        let entry = try #require(try await reader(fixture).entries().first)
        #expect(entry.kind == .voiceNote)
        guard case .file(let url) = entry.media else {
            Issue.record("no file")
            return
        }
        #expect(url.lastPathComponent == "note.opus")
    }

    @Test func mediaWithNoPathOrNoFileIsNotDownloaded() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.message(chat: 1, type: 8, text: nil, mediaPath: nil)
        try fixture.message(chat: 1, type: 3, text: nil, mediaPath: "Media/gone.opus")
        let entries = try await reader(fixture).entries()
        #expect(entries.map(\.media) == [.notDownloaded, .notDownloaded])
    }

    @Test func aPathOutsideTheMessageFolderIsNotDownloaded() async throws {
        let fixture = try WhatsAppFixture()
        try Data("secret".utf8).write(to: fixture.container.appending(path: "outside.pdf"))
        try fixture.message(chat: 1, type: 8, text: nil, mediaPath: "../outside.pdf")
        #expect(try await reader(fixture).entries().first?.media == .notDownloaded)
    }

    @Test func otherMessageTypesAreSkipped() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.message(chat: 1, type: 1, text: nil, mediaPath: "Media/photo.jpg")
        #expect(try await reader(fixture).entries().isEmpty)
    }

    @Test func theDefaultPolicyDeniesWhatsApp() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.message(chat: 1, type: 0, text: "hello")
        let off = FixedPolicy(policy: CapturePolicy())
        await #expect(throws: ReadError.denied(.sourceSwitchedOff)) { try await reader(fixture, policy: off).entries() }
    }

    @Test func aDeniedChatIsNotRead() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.message(chat: 1, type: 0, text: "hello")
        let denied = FixedPolicy(
            policy: CapturePolicy(switches: [.whatsapp: true], denyList: [.whatsapp: [selfJID]]))
        await #expect(throws: ReadError.denied(.labelDenied)) { try await reader(fixture, policy: denied).entries() }
    }

    @Test func switchedOnWithNoChatAllowedNothingIsRead() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.message(chat: 1, type: 0, text: "hello")
        let noList = FixedPolicy(policy: CapturePolicy(switches: [.whatsapp: true]))
        await #expect(throws: ReadError.denied(.labelNotAllowed)) {
            try await reader(fixture, policy: noList).entries()
        }
        #expect(try await reader(fixture).entries().map(\.text) == ["hello"])
    }

    @Test func aMissingStoreIsUnreadable() async throws {
        let empty = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let missing = WhatsAppChatReader(container: empty, chatJID: selfJID, policy: whatsappOn)
        await #expect(throws: ReadError.unreadableStore) { try await missing.entries() }
    }
    @Test func aGroupGivesEachSenderByNameAndTheFounderAsMe() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.message(chat: 4, type: 0, text: "update?", date: 100)
        try fixture.message(chat: 4, type: 0, text: "api done", member: 1, date: 200)
        try fixture.message(chat: 4, type: 0, text: "kal tak", member: 2, date: 300)
        try fixture.message(chat: 5, type: 0, text: "dinner?", member: 4, date: 150)
        let entries = try await reader(fixture, chat: groupJID).entries()
        #expect(entries.map(\.text) == ["update?", "api done", "kal tak"])
        #expect(
            entries.map(\.sender) == [
                .me, .member(jid: "a@s.whatsapp.net", name: "Asha"), .member(jid: "b@s.whatsapp.net", name: "Bharat"),
            ])
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

    @Test func membersAreTheActiveOnesByName() async throws {
        let fixture = try WhatsAppFixture()
        let members = try await reader(fixture, chat: groupJID).members()
        #expect(members.map(\.name) == ["Asha", "Bharat"])
    }

    @Test func anAllowListLetsOnlyItsGroupBeRead() async throws {
        let fixture = try WhatsAppFixture()
        try fixture.message(chat: 4, type: 0, text: "team", member: 1)
        let onlyTeam = FixedPolicy(
            policy: CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [groupJID]]))
        #expect(try await reader(fixture, chat: groupJID, policy: onlyTeam).entries().map(\.text) == ["team"])
        await #expect(throws: ReadError.denied(.labelNotAllowed)) {
            try await reader(fixture, chat: otherGroupJID, policy: onlyTeam).entries()
        }
        await #expect(throws: ReadError.denied(.labelNotAllowed)) {
            try await reader(fixture, chat: otherGroupJID, policy: onlyTeam).members()
        }
    }

    @Test func groupsAreListedNewestFirstOnlyWhileWhatsAppIsOn() throws {
        let fixture = try WhatsAppFixture()
        let groups = try WhatsAppChatReader.groups(container: fixture.container, policy: whatsappOn.policy)
        #expect(groups.map(\.name) == ["Team", "Family"])
        #expect(throws: ReadError.denied(.sourceSwitchedOff)) {
            try WhatsAppChatReader.groups(container: fixture.container, policy: CapturePolicy())
        }
        #expect(throws: ReadError.denied(.captureOff)) {
            try WhatsAppChatReader.groups(
                container: fixture.container, policy: CapturePolicy(mode: .off, switches: [.whatsapp: true]))
        }
    }
}
