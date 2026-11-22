import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import LocalSources

/// The two ways a one-to-one chat reaches the evidence store, the Mac's WhatsApp store and the WhatsApp Web page,
/// give one line for one message when their words match, and never write one chat at the same time.
@Suite struct WhatsAppWebPathTests {
    private typealias Rig = WhatsAppEvidenceTests.Rig

    /// Chat 2 of the fixture is a one-to-one chat with `otherJID`: FIRST from the friend, SECOND from the founder.
    private func rig() throws -> Rig {
        let rig = try Rig(allowing: [otherJID])
        try rig.fixture.message(chat: 2, type: 0, text: "Send the deck Friday.", stanza: "FIRST", pk: 1)
        try rig.fixture.run("UPDATE ZWAMESSAGE SET ZISFROMME = 0 WHERE Z_PK = 1")
        try rig.fixture.message(chat: 2, type: 0, text: "I will review it Monday.", stanza: "SECOND", pk: 2)
        return rig
    }

    private func page(first: String = "Send the deck Friday.", extra: [String] = []) throws -> Data {
        let messages: [[String: String]] =
            [
                ["id": "false_919800000002@c.us_FIRST", "text": first],
                ["id": "true_919800000002@c.us_SECOND", "text": "I will review it Monday."],
            ] + extra.map { ["id": "false_919800000002@c.us_\($0)", "text": "new \($0)"] }
        return try JSONSerialization.data(withJSONObject: [
            "type": "whatsapp_web", "browser": "com.brave.Browser", "url": "https://web.whatsapp.com/",
            "messages": messages,
        ])
    }

    private func intake(readable: Set<String>) -> WhatsAppWebIntake {
        WhatsAppWebIntake(
            owner: .success(WhatsAppEvidenceTests.owner), readableSources: { readable },
            zone: TimeZone(identifier: "UTC")!)
    }

    private func lineIDs(_ rig: Rig) throws -> [String] {
        try rig.rows("SELECT hex(line_id) FROM evidence ORDER BY id").compactMap { $0.text(0) }
    }

    @Test func aPageReadFirstThenTheStoreReaderGiveOneLinePerMessage() async throws {
        let rig = try rig()
        #expect(PageHost.answer(try page(), store: rig.store, whatsApp: intake(readable: [])).kept)
        let fromPage = try lineIDs(rig)
        #expect(fromPage.count == 2)

        let report = try await rig.ingest([otherJID])
        #expect(report.inserted == 0 && report.seenAgain == 2, "the same two lines, seen again")
        #expect(try lineIDs(rig) == fromPage)
        #expect(try rig.count("SELECT count(DISTINCT entity_key) FROM evidence") == 2)
    }

    @Test func theStoreReaderFirstThenAPageGiveOneLinePerMessage() async throws {
        let rig = try rig()
        try await rig.ingest([otherJID])
        let fromStore = try lineIDs(rig)
        #expect(fromStore.count == 2)

        let reply = PageHost.answer(try page(), store: rig.store, whatsApp: intake(readable: []))
        #expect(reply == PageHost.Reply(kept: false), "nothing new")
        #expect(try lineIDs(rig) == fromStore)
    }

    @Test func otherWordsForOneMessageLookLikeAnEditAndTheOldVersionStays() async throws {
        let rig = try rig()
        _ = PageHost.answer(
            try page(first: "Send the deck Friday @Ana"), store: rig.store, whatsApp: intake(readable: []))
        try await rig.ingest([otherJID])
        #expect(try rig.count("SELECT count(*) FROM evidence") == 3)
        #expect(try rig.count("SELECT count(DISTINCT entity_key) FROM evidence") == 2, "two texts, one entity key")
    }

    @Test func fullDiskAccessGrantedLaterMovesTheChatToTheStoreReader() async throws {
        let rig = try rig()
        let readable = Mutex<Set<String>>([])
        let intake = WhatsAppWebIntake(
            owner: .success(WhatsAppEvidenceTests.owner), readableSources: { readable.withLock { $0 } })
        #expect(PageHost.answer(try page(), store: rig.store, whatsApp: intake).kept)

        readable.withLock { $0 = [SourceDescriptor.whatsAppChat.key] }
        let refused = PageHost.answer(try page(extra: ["LATER"]), store: rig.store, whatsApp: intake)
        #expect(refused.kept == false && refused.error == "storeReaderReads")
        #expect(try rig.count("SELECT count(*) FROM evidence") == 2, "the page wrote no new line")

        try rig.fixture.message(chat: 2, type: 0, text: "new LATER", stanza: "LATER", pk: 3)
        let report = try await rig.ingest([otherJID])
        #expect(report.inserted == 1 && report.seenAgain == 2)
    }
}
