import Foundation
import GRDB
import Kernel
import Lines
import Testing

@testable import WorkbenchCore

/// The WhatsApp Web page as an evidence source: the same lines, keys and consent as the store reader, for one-to-one
/// chats, and only while the store reader cannot read the chat.
@Suite struct WhatsAppWebTests {
    static let chat = "919800000001@s.whatsapp.net"
    static let allowed = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [chat]])
    static let zone = TimeZone(identifier: "Asia/Kolkata")!

    static func intake(readable: Set<String> = []) -> WhatsAppWebIntake {
        WhatsAppWebIntake(owner: .success(try! PersonID("test-owner")), readableSources: { readable }, zone: zone)
    }

    static func message(_ id: String, _ text: String?, sent: String? = nil, deleted: Bool = false) -> [String: Any] {
        var message: [String: Any] = ["id": id]
        if let text { message["text"] = text }
        if deleted { message["deleted"] = true }
        if let sent { message["sent"] = sent }
        return message
    }

    static func snapshot(
        _ messages: [[String: Any]], url: String = "https://web.whatsapp.com/", browser: String = "com.brave.Browser"
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "whatsapp_web", "browser": browser, "url": url, "messages": messages,
        ])
    }

    static func status() -> Data { Data(#"{"type":"whatsapp_status"}"#.utf8) }

    static var first: [String: Any] {
        message("false_919800000001@c.us_FIRST", "Send the deck Friday.", sent: "3:45 PM, 11/22/2026")
    }

    static var second: [String: Any] {
        message("true_919800000001@c.us_SECOND", "I will review it Monday.", sent: "3:50 PM, 11/22/2026")
    }

    private func world(policy: CapturePolicy = allowed) throws -> EvidenceIngestTests.World {
        let world = try EvidenceIngestTests.World(allowing: [])
        try world.store.savePolicy(policy)
        return world
    }

    private func store(policy: CapturePolicy = allowed) throws -> Store { try world(policy: policy).store }

    private func rows(_ store: Store, _ columns: String = "text") throws -> [Row] {
        try store.writer.read { try Row.fetchAll($0, sql: "SELECT \(columns) FROM evidence ORDER BY id") }
    }

    private func answer(_ data: Data, _ store: Store, readable: Set<String> = []) -> PageHost.Reply {
        PageHost.answer(data, store: store, whatsApp: Self.intake(readable: readable))
    }

    // MARK: lines

    @Test func aDirectChatIsWrittenWithTheKeysTheStoreReaderUses() throws {
        let store = try store()
        let reply = answer(try Self.snapshot([Self.first, Self.second]), store)
        #expect(reply == PageHost.Reply(kept: true))
        let stored = try rows(
            store, "line_id, entity_key, container, actor, event_time, audience_digest, obtained_by, grant_id, text")
        #expect(stored.map { $0["text"] as String } == ["Send the deck Friday.", "I will review it Monday."])
        let theirs = try EntityKey.whatsAppDirect(chat: Self.chat, fromMe: false, stanzaID: "FIRST")
        let mine = try EntityKey.whatsAppDirect(chat: Self.chat, fromMe: true, stanzaID: "SECOND")
        #expect(stored.map { $0["entity_key"] as Data } == [Data(theirs.bytes), Data(mine.bytes)])
        #expect(
            stored[0]["line_id"] as Data
                == Data(Line(entity: theirs, text: "Send the deck Friday.", readerVersion: "x").id.bytes),
            "the line id is the one the store reader gives the same message")
        #expect(stored.map { $0["container"] as String } == [Self.chat, Self.chat])
        #expect(stored.map { $0["actor"] as String } == [Self.chat, "me"])
        #expect(stored.map { $0["obtained_by"] as String } == ["dom_text", "dom_text"])
        #expect(stored.map { $0["grant_id"] as String } == ["whatsapp:\(Self.chat)", "whatsapp:\(Self.chat)"])
        let audience = Data(AudienceDigest(owner: WhatsAppAudience.owner, members: [Self.chat]).bytes)
        #expect(stored.allSatisfy { $0["audience_digest"] as Data == audience })
        let sent = Int64(
            try #require(ISO8601DateFormatter().date(from: "2026-11-22T10:15:00Z")).timeIntervalSince1970 * 1000)
        #expect(stored[0]["event_time"] as Int64 == sent, "3:45 PM in Kolkata on 22 November")
        #expect(try store.queries.state(forKey: Store.cursorKey(grantID: "whatsapp:\(Self.chat)")) == nil)
    }

    @Test func readingTheSamePageAgainWritesNothingNew() throws {
        let store = try store()
        _ = answer(try Self.snapshot([Self.first, Self.second]), store)
        let again = answer(try Self.snapshot([Self.first, Self.second]), store)
        #expect(again == PageHost.Reply(kept: false))
        #expect(try rows(store).count == 2)
        let edited = Self.message("false_919800000001@c.us_FIRST", "Send the deck Monday.", sent: "3:45 PM, 11/22/2026")
        #expect(answer(try Self.snapshot([edited]), store).kept)
        #expect(try rows(store).count == 3, "an edit is a new version of the same message; the old one stays")
    }

    @Test func aMessageThePageShowsAsDeletedBecomesATombstoneThatErasesItsWords() throws {
        let world = try world()
        let store = world.store
        let word = EvidenceIngestTests.word()
        let said = Self.message("false_919800000001@c.us_GONE", "\(word) is the plan", sent: "3:45 PM, 11/22/2026")
        _ = answer(try Self.snapshot([said, Self.second]), store)
        #expect(try world.copies(of: word) > 0)

        let deleted = Self.message("false_919800000001@c.us_GONE", nil, deleted: true)
        #expect(answer(try Self.snapshot([deleted, Self.second]), store).kept)
        #expect(
            try rows(store, "tombstone, text").map { "\($0["tombstone"] as Int):\($0["text"] as String)" }
                == ["0:I will review it Monday.", "1:"])
        #expect(try world.copies(of: word) == 0)

        _ = answer(try Self.snapshot([said]), store)
        #expect(try rows(store).count == 2, "a deleted message is not written again")
    }

    // MARK: consent

    @Test func nothingIsWrittenForAChatThePolicyDoesNotAllow() throws {
        let page = try Self.snapshot([Self.first])
        let other = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: ["919800000009@s.whatsapp.net"]])
        let switchedOff = CapturePolicy(switches: [.whatsapp: false], allowList: [.whatsapp: [Self.chat]])
        var denied = Self.allowed
        denied.denyList[.whatsapp] = [Self.chat]
        var paused = Self.allowed
        paused.mode = .paused(until: t0.addingTimeInterval(3600))
        for policy in [CapturePolicy(), other, switchedOff, denied, paused] {
            let store = try store(policy: policy)
            #expect(answer(page, store).kept == false)
            #expect(try rows(store).isEmpty)
        }
        #expect(answer(page, try store()).kept, "the same page is kept when the chat is allowed")
    }

    /// A revoke that commits after the check and before the write must stop the write: the check is in the write
    /// transaction. The test holds the writer in a transaction that revokes the chat, and sends the page meanwhile.
    @Test func aRevokeThatCommitsFirstStopsAWriteThatAlreadyPassedTheFirstCheck() throws {
        let store = try store()
        let revoked = try Coding.json(CapturePolicy(switches: [.whatsapp: true]))
        let holding = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            try? store.writer.write { db in
                holding.signal()
                Thread.sleep(forTimeInterval: 0.3)
                try db.execute(
                    sql: "INSERT INTO consent(ts, policy) VALUES (?, ?)", arguments: [store.clock().stored, revoked])
            }
            done.signal()
        }
        holding.wait()
        let reply = answer(try Self.snapshot([Self.first]), store)
        done.wait()
        #expect(reply.kept == false && reply.error != nil)
        #expect(try rows(store).isEmpty)
    }

    // MARK: fallback

    @Test func theStoreReaderAndThePageNeverWriteOneChatAtTheSameTime() throws {
        let readable: Set<String> = [SourceDescriptor.whatsAppChat.key]
        #expect(SourceRegistry.mayWrite(.whatsAppWeb, whileReadable: []))
        #expect(!SourceRegistry.mayWrite(.whatsAppWeb, whileReadable: readable))
        #expect(SourceRegistry.mayWrite(.whatsAppChat, whileReadable: readable), "the primary source has no fallback")

        let store = try store()
        let page = try Self.snapshot([Self.first])
        #expect(answer(Self.status(), store, readable: readable).chats == [])
        #expect(answer(page, store, readable: readable).error == "storeReaderReads")
        #expect(try rows(store).isEmpty)
        #expect(answer(Self.status(), store).chats == [Self.chat])
        #expect(answer(page, store).kept)
    }

    // MARK: snapshot checks

    @Test func aSnapshotThatBreaksAnyRuleIsRefusedWholeBeforeAnyWrite() throws {
        let one = Self.first
        let tooLong = Self.message("false_919800000001@c.us_HUGE", String(repeating: "x", count: 20_001))
        let many = (0...200).map { Self.message("false_919800000001@c.us_M\($0)", "m\($0)") }
        let broken: [Data] = try [
            Self.snapshot([one], url: "https://web.whatsapp.com.example/"),
            Self.snapshot([one], url: "https://sub.web.whatsapp.com/"),
            Self.snapshot([one], url: "http://web.whatsapp.com/"),
            Self.snapshot([one], url: "https://user@web.whatsapp.com/"),
            Self.snapshot([one], browser: "com.evil.app"),
            Self.snapshot([one, Self.message("false_919800000002@c.us_OTHER", "from another chat")]),
            Self.snapshot([one, Self.message("unexpected-layout", "no id")]),
            Self.snapshot([tooLong]),
            Self.snapshot(many),
            Self.snapshot([]),
            Self.snapshot([one, one]),
            Self.snapshot([Self.message("false_919800000001@c.us_EMPTY", "  ")]),
            Self.snapshot([Self.message("false_919800000001@c.us_BOTH", "words", deleted: true)]),
        ]
        let store = try store()
        for page in broken {
            #expect(answer(page, store).kept == false)
        }
        #expect(try rows(store).isEmpty)
        #expect(try broken.map { try JSONDecoder().decode(WhatsAppWebSnapshot.self, from: $0) }.count == broken.count)
    }

    @Test func theLimitsHoldAtTheirEdge() throws {
        let edge = (0..<200).map { Self.message("false_919800000001@c.us_E\($0)", "m") }
        #expect(answer(try Self.snapshot(edge), try store()).kept, "200 messages pass")
        let characters = Self.message("false_919800000001@c.us_BIG", String(repeating: "x", count: 20_000))
        #expect(answer(try Self.snapshot([characters]), try store()).kept, "20,000 characters pass")
    }

    @Test func theMessageIdNamesTheChatTheSenderAndTheStanza() {
        let theirs = WebMessageID("false_919800000001@c.us_3EB0ABC")
        #expect(theirs == WebMessageID("false_919800000001@s.whatsapp.net_3EB0ABC"))
        #expect(theirs?.fromMe == false && theirs?.chat == "919800000001@s.whatsapp.net" && theirs?.stanza == "3EB0ABC")
        #expect(WebMessageID("true_919800000001@c.us_X")?.fromMe == true)
        #expect(WebMessageID("false_123-456@g.us_X_77@lid")?.chat == "123-456@g.us")
        for bad in [
            "", "false_x@c.us_X", "false_1@evil.example_X", "maybe_1@c.us_X", "false_1@c.us_", "false_1@c.us_X Y",
        ] {
            #expect(WebMessageID(bad) == nil, "\(bad)")
        }
    }

    // MARK: stamps

    @Test func aStampBecomesATimeOnlyWhenItsDayAndMonthCanBeTold() throws {
        func iso(_ text: String) -> UTCInstant? {
            ISO8601DateFormatter().date(from: text).map(UTCInstant.init)
        }
        let kolkata = Self.zone
        #expect(
            WebSentStamp.instants(["3:45 PM, 11/22/2026", "12:05 AM, 11/23/2026"], in: kolkata)
                == [iso("2026-11-22T10:15:00Z"), iso("2026-11-22T18:35:00Z")], "22 and 23 settle month first")
        #expect(WebSentStamp.instants(["15:45, 22/11/2026"], in: kolkata) == [iso("2026-11-22T10:15:00Z")])
        #expect(
            WebSentStamp.instants(["15:45, 22/11/2026", "09:00, 05/11/2026"], in: kolkata)[1]
                == iso("2026-11-05T03:30:00Z"))
        #expect(WebSentStamp.instants(["3:45 PM, 03/04/2026"], in: kolkata) == [nil], "03/04 could be either")
        #expect(WebSentStamp.instants(["3:45 PM, 05/05/2026"], in: kolkata)[0] != nil, "05/05 is the same either way")
        #expect(
            WebSentStamp.instants(["15:45, 22/11/2026", "3:45 PM, 11/22/2026"], in: kolkata) == [nil, nil],
            "both orders")
        for bad in [
            nil, "", "yesterday", "25:00, 22/11/2026", "13:00 PM, 22/11/2026", "3:45 PM, 31/31/2026",
            "3:45 PM, 02/30/2026",
        ] {
            #expect(WebSentStamp.instants([bad], in: kolkata) == [nil], "\(bad ?? "nil")")
        }
    }
}
