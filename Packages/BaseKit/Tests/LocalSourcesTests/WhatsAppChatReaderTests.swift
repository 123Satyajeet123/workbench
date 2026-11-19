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

}
