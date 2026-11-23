import Foundation
import Kernel
import Lines
import Synchronization
import Testing
import WorkbenchCore

@testable import LocalSources

/// The WhatsApp reader as an evidence source, on a fixture store (never the live one): types, identity, replies,
/// audience, the cursor, a revoke, the header check. The store side is tested in `EvidenceIngestTests`.
@Suite struct WhatsAppEvidenceTests {
    static let owner = try! PersonID("owner-1")
    /// The reader's "now": 2,000 s after Core Data's epoch. Messages at date 1,000 are inside the 3-day window.
    static let now = Date(timeIntervalSinceReferenceDate: 2000)
    static let later = Date(timeIntervalSinceReferenceDate: 2000 + 10 * 86_400)

    /// A fixture store, an evidence store whose policy allows its chats, and a clock the test moves.
    struct Rig {
        final class Clock: Sendable {
            let now = Mutex(WhatsAppEvidenceTests.now)
        }

        let fixture: WhatsAppFixture
        let store: Store
        let clock = Clock()

        init(allowing chats: [String] = [groupJID, selfJID, otherJID]) throws {
            fixture = try WhatsAppFixture()
            let clock = clock
            store = try Store(
                directory: FileManager.default.temporaryDirectory.appending(path: "wb-\(UUID().uuidString)"),
                clock: { clock.now.withLock { $0 } })
            try store.savePolicy(CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: Set(chats)]))
        }

        var now: Date { clock.now.withLock { $0 } }

        func move(to date: Date) { clock.now.withLock { $0 = date } }

        func reader(_ chats: [String] = [groupJID]) -> WhatsAppChatReader {
            WhatsAppChatReader(container: fixture.container, chatJIDs: chats, policy: store)
        }

        @discardableResult
        func ingest(_ chats: [String] = [groupJID]) async throws -> IngestReport {
            try await store.ingest(reader(chats), owner: WhatsAppEvidenceTests.owner, now: now)
        }

        /// Rows of the evidence store, read through a read-only connection to its file.
        func rows(_ sql: String) throws -> [SQLiteRow] {
            try ReadOnlyDatabase(path: store.directory.appending(path: "workbench.sqlite").path).rows(sql)
        }

        func count(_ sql: String) throws -> Int { Int(try rows(sql).first?.integer(0) ?? 0) }

        func texts() throws -> [String] {
            try rows("SELECT text FROM evidence WHERE tombstone = 0 ORDER BY id").compactMap { $0.text(0) }
        }

        func copies(of word: String) throws -> Int {
            try ["workbench.sqlite", "workbench.sqlite-wal"].reduce(0) { total, name in
                let data = (try? Data(contentsOf: store.directory.appending(path: name))) ?? Data()
                var found = 0
                var from = data.startIndex
                while let range = data.range(of: Data(word.utf8), in: from..<data.endIndex) {
                    found += 1
                    from = range.upperBound
                }
                return total + found
            }
        }
    }

    // MARK: Types

    /// The 31 type codes measured on the founder's store, with whether the type carries text there.
    static let measured = MeasuredWhatsAppTypes.types

    @Test func everyMeasuredTypeIsAMappedLineATombstoneOrACountedSkip() async throws {
        let rig = try Rig()
        for (index, entry) in Self.measured.enumerated() {
            // A revoked row holds an opaque string in its text on 16 of 152 rows: it must not be stored.
            try rig.fixture.message(
                chat: 4, type: entry.code, text: entry.hasText ? "type \(entry.code) words" : nil, member: 1,
                date: 1000, pk: 100 + index)
        }
        let report = try await rig.ingest()
        let expectedLines = Self.measured.filter { $0.hasText && ![6, 10, 14].contains($0.code) }.map(\.code)
        #expect(report.inserted == expectedLines.count && report.tombstones == 1)
        #expect(
            try rig.texts() == Self.measured.filter { expectedLines.contains($0.code) }.map { "type \($0.code) words" })
        #expect(report.census.count == 31)
        #expect(report.census.values.map(\.rows).reduce(0, +) == 31)
        #expect(report.census[6] == TypeCensus(rows: 1, rowsWithText: 1), "a system notice is counted, not stored")
        #expect(report.census[1] == TypeCensus(rows: 1, rowsWithText: 0))
        #expect(report.unkeyed == 0)
        #expect(try rig.copies(of: "type 14 words") == 0, "the opaque text of a revoked row is never stored")
        #expect(try rig.copies(of: "type 6 words") == 0)
    }

    @Test func aLinkMessageIsALineAndAnUnnamedTypeWithTextIsRead() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 7, text: "see https://example.org/deck", member: 1, pk: 11)
        try rig.fixture.message(chat: 4, type: 42, text: "an unnamed type", member: 1, pk: 12)
        try await rig.ingest()
        #expect(try rig.texts() == ["see https://example.org/deck", "an unnamed type"])
    }

    @Test func aCaptionAndATextShareOneLineAndAnEmptyMediaRowHasNone() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 8, text: "see this", title: "deck.pdf", member: 1, pk: 11)
        try rig.fixture.message(chat: 4, type: 1, text: nil, title: "photo caption", member: 1, pk: 12)
        try rig.fixture.message(chat: 4, type: 1, text: nil, title: nil, member: 1, pk: 13)
        try await rig.ingest()
        #expect(try rig.texts() == ["deck.pdf — see this", "photo caption"])
    }

    // MARK: Identity

    @Test func aMessageIsKeyedByChatAuthorAndStanzaIDAndStoredWithItsActorTimeAndAudience() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "from a member", member: 1, date: 1000, stanza: "ST1", pk: 11)
        try rig.fixture.message(chat: 4, type: 0, text: "from me", date: 1001, stanza: "ST2", pk: 12)
        try await rig.ingest()
        let member = try EntityKey.whatsAppGroup(
            chat: groupJID, author: .member("a@s.whatsapp.net"), stanzaID: "ST1")
        let me = try EntityKey.whatsAppGroup(chat: groupJID, author: .me, stanzaID: "ST2")
        let stored = try rig.rows("SELECT entity_key, actor, event_time, container, quality FROM evidence ORDER BY id")
        #expect(
            stored.map { $0.blob(0) } == [member.bytes, me.bytes], "a group message is keyed by its member, me as me")
        #expect(stored.map { $0.text(1) } == ["a@s.whatsapp.net", "me"])
        let epoch: Int64 = 978_307_200_000
        let expectedTimes: [Int64] = [epoch + 1_000_000, epoch + 1_001_000]
        #expect(stored.map { $0.integer(2) } == expectedTimes)
        #expect(stored.allSatisfy { $0.text(3) == groupJID && $0.text(4) == "stable" })
    }

    @Test func aDirectChatKeyHasNoMemberAndNamesTheOtherPersonAsActor() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 2, type: 0, text: "hi", member: nil, stanza: "D1", pk: 11)
        try rig.fixture.run("UPDATE ZWAMESSAGE SET ZISFROMME = 0 WHERE Z_PK = 11")
        try await rig.ingest([otherJID])
        let key = try EntityKey.whatsAppDirect(chat: otherJID, fromMe: false, stanzaID: "D1")
        let row = try #require(try rig.rows("SELECT entity_key, actor FROM evidence").first)
        #expect(row.blob(0) == key.bytes && row.text(1) == otherJID)
    }

    /// One `(chat, author, stanza)` pair repeats once in 28,719 messages: both rows get a line, told apart by their
    /// row order, both `derived`.
    @Test func aRepeatedStanzaIDGivesTwoDerivedLines() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "first copy", member: 1, stanza: "DUP", pk: 11)
        try rig.fixture.message(chat: 4, type: 0, text: "second copy", member: 1, stanza: "DUP", pk: 12)
        try rig.fixture.message(chat: 4, type: 0, text: "alone", member: 1, stanza: "ONE", pk: 13)
        try await rig.ingest()
        let stored = try rig.rows("SELECT text, quality FROM evidence ORDER BY id")
        #expect(stored.map { $0.text(0) } == ["first copy", "second copy", "alone"])
        #expect(stored.map { $0.text(1) } == ["derived", "derived", "stable"])
        #expect(try rig.count("SELECT count(DISTINCT entity_key) FROM evidence") == 3)
    }

    @Test func aRowWithNoStanzaIDOrNoGroupMemberIsCountedAndNotWritten() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "no stanza", member: 1, pk: 11)
        try rig.fixture.run("UPDATE ZWAMESSAGE SET ZSTANZAID = NULL WHERE Z_PK = 11")
        try rig.fixture.message(chat: 4, type: 0, text: "no member", member: 1, pk: 12)
        try rig.fixture.run("UPDATE ZWAMESSAGE SET ZGROUPMEMBER = NULL, ZISFROMME = 0 WHERE Z_PK = 12")
        try rig.fixture.message(chat: 4, type: 0, text: "fine", member: 1, pk: 13)
        let report = try await rig.ingest()
        #expect(report.unkeyed == 2 && report.inserted == 1)
    }

    // MARK: Replies

    @Test func aReplyPointsAtTheKeyOfTheQuotedMessageWhenItIsInTheChat() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "question?", member: 2, stanza: "Q1", pk: 11)
        try rig.fixture.message(chat: 4, type: 0, text: "answer", member: 1, stanza: "A1", pk: 12, reply: "Q1")
        try rig.fixture.message(chat: 4, type: 0, text: "old thread", member: 1, stanza: "A2", pk: 13, reply: "GONE")
        try await rig.ingest()
        let quoted = try EntityKey.whatsAppGroup(
            chat: groupJID, author: .member("b@s.whatsapp.net"), stanzaID: "Q1")
        let replies = try rig.rows("SELECT text, reply_to FROM evidence ORDER BY id")
        #expect(replies.map { $0.blob(1) } == [nil, quoted.bytes, nil], "a quote outside the store has no target")
    }

    // MARK: Audience

    @Test func theAudienceIsTheActiveMembersAndMeNotThoseWhoLeft() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "hello", member: 1, pk: 11)
        try await rig.ingest()
        let digest = try #require(try rig.rows("SELECT audience_digest FROM evidence").first?.blob(0))
        #expect(digest == AudienceDigest(owner: "me", members: ["a@s.whatsapp.net", "b@s.whatsapp.net"]).bytes)
        #expect(
            digest
                != AudienceDigest(owner: "me", members: ["a@s.whatsapp.net", "b@s.whatsapp.net", "c@s.whatsapp.net"])
                .bytes)
    }

    @Test func aDirectChatsAudienceIsTheOtherPersonAndMe() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 2, type: 0, text: "hi", pk: 11)
        try await rig.ingest([otherJID])
        let digest = try #require(try rig.rows("SELECT audience_digest FROM evidence").first?.blob(0))
        #expect(digest == AudienceDigest(owner: "me", members: [otherJID]).bytes)
    }

    @Test func aGroupWithNoActiveMemberFailsClosedAndTheOtherChatsAreStillRead() async throws {
        let rig = try Rig()
        try rig.fixture.run("UPDATE ZWAGROUPMEMBER SET ZISACTIVE = 0 WHERE ZCHATSESSION = 4")
        try rig.fixture.message(chat: 4, type: 0, text: "who can read this", member: 1, pk: 11)
        try rig.fixture.message(chat: 2, type: 0, text: "a direct hello", pk: 12)
        let report = try await rig.ingest([groupJID, otherJID])
        #expect(report.failures.map(\.label) == [groupJID])
        #expect(report.failures.first?.error as? ReadError == .audienceUnknown)
        #expect(try rig.texts() == ["a direct hello"], "the group wrote nothing, the direct chat was read")
    }

    @Test func aChatTheStoreDoesNotKnowIsNothingToReadAndNoFailure() async throws {
        let rig = try Rig(allowing: [groupJID, "999@g.us"])
        try rig.fixture.message(chat: 4, type: 0, text: "x", member: 1, pk: 11)
        let report = try await rig.ingest([groupJID, "999@g.us"])
        #expect(report.failures.isEmpty && report.inserted == 1)
    }

    // MARK: Cursor and re-read

    @Test func aReadAgainAddsNoRowsAndANewMessageAddsOne() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "one", member: 1, pk: 11)
        try rig.fixture.message(chat: 4, type: 6, text: "a group event", member: 1, pk: 12)
        let first = try await rig.ingest()
        #expect(first.inserted == 1)
        let cursor = try rig.store.scanState(kind: .whatsapp, label: groupJID).cursor
        #expect(cursor?.storeID == "STORE-UUID-1" && cursor?.lastRow == 12, "the cursor passes a skipped row too")
        rig.move(to: rig.now.addingTimeInterval(60))
        let second = try await rig.ingest()
        #expect(second.inserted == 0 && second.seenAgain == 1)
        try rig.fixture.message(chat: 4, type: 0, text: "two", member: 1, pk: 13)
        let third = try await rig.ingest()
        #expect(third.inserted == 1 && third.seenAgain == 1)
        #expect(try rig.count("SELECT count(*) FROM evidence") == 2)
    }

    /// Row numbers, not dates: a message that arrives late (history sync) with an old date is still read.
    @Test func aLateMessageWithAnOldDateIsReadBecauseItsRowNumberIsNew() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "recent", member: 1, date: 1_000_000, pk: 11)
        rig.move(to: Self.later)
        try await rig.ingest()
        try rig.fixture.message(chat: 4, type: 0, text: "synced late", member: 1, date: 10, pk: 12)
        let report = try await rig.ingest()
        #expect(report.inserted == 1)
        #expect(try rig.texts() == ["recent", "synced late"])
    }

    @Test func aMessageOutsideTheWindowIsNotReadAgain() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "old", member: 1, date: 1000, pk: 11)
        rig.move(to: Self.later)
        try await rig.ingest()
        rig.move(to: Self.later.addingTimeInterval(60))
        let report = try await rig.ingest()
        #expect(report.inserted == 0 && report.seenAgain == 0, "no row is read: it is below the cursor and too old")
    }

    @Test func aTextEditedInsideTheWindowIsANewLineOfTheSameMessage() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "meet at 5", member: 1, pk: 11)
        try await rig.ingest()
        try rig.fixture.run("UPDATE ZWAMESSAGE SET ZTEXT = 'meet at 6' WHERE Z_PK = 11")
        let report = try await rig.ingest()
        #expect(report.inserted == 1)
        #expect(try rig.count("SELECT count(DISTINCT entity_key) FROM evidence") == 1)
        #expect(try rig.texts() == ["meet at 5", "meet at 6"])
    }

    // MARK: Store identity

    @Test func aChangedStoreIdentityVoidsTheCursorAndReadsEverythingAgain() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "old one", member: 1, date: 1000, pk: 11)
        try rig.fixture.message(chat: 4, type: 0, text: "old two", member: 1, date: 1001, pk: 12)
        rig.move(to: Self.later)
        try await rig.ingest()
        rig.move(to: Self.later.addingTimeInterval(60))
        #expect(try await rig.ingest().seenAgain == 0, "same store: below the cursor, outside the window")
        try rig.fixture.changeStoreIdentity(to: "STORE-UUID-2")
        let renumbered = try await rig.ingest()
        #expect(renumbered.seenAgain == 2 && renumbered.inserted == 0, "a new store: every row is read, none is new")
        let cursor = try rig.store.scanState(kind: .whatsapp, label: groupJID).cursor
        #expect(cursor?.storeID == "STORE-UUID-2" && cursor?.lastRow == 12)
    }

    /// The numbers of a new store mean other rows: only the first read of a chat maps old citation ids.
    @Test func oldCitationIDsAreMappedOnTheFirstReadOnly() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "old one", member: 1, pk: 11)
        try await rig.ingest()
        #expect(try rig.count("SELECT count(*) FROM evidence_legacy WHERE space = 'wa_zpk' AND ref = 11") == 1)
        try rig.fixture.changeStoreIdentity(to: "STORE-UUID-2")
        try rig.fixture.message(chat: 4, type: 0, text: "new store row", member: 1, pk: 500)
        try await rig.ingest()
        #expect(try rig.count("SELECT count(*) FROM evidence_legacy") == 1, "the new store's row 500 is not mapped")
    }

    // MARK: Header

    @Test func aFileThatDoesNotStartWithTheSQLiteHeaderIsRefusedBeforeAnyRead() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "x", member: 1, pk: 11)
        #expect(try await rig.ingest().inserted == 1, "the same file with a good header is read")
        let file = rig.fixture.container.appending(path: "ChatStorage.sqlite")
        let good = try Data(contentsOf: file)
        for bad in [Data((0..<4096).map { UInt8($0 % 251) }), Data("SQLite format 2\0".utf8) + good.dropFirst(16)] {
            try bad.write(to: file)
            await #expect(throws: ReadError.notADatabase) { try await rig.ingest() }
        }
        try good.write(to: file)
        #expect(try await rig.ingest().seenAgain == 1)
    }

    // MARK: Revoke

    /// The founder's decision: a message deleted for everyone loses its stored text. The store rewrites the row in
    /// place as type 14 with no text.
    @Test func aRevokeErasesTheStoredTextAndLeavesATombstone() async throws {
        let rig = try Rig()
        let secret = "zxq\(UInt32.random(in: 100_000...999_999))secret"
        for number in 0..<200 {
            try rig.fixture.message(chat: 4, type: 0, text: "common words here \(number)", member: 1, pk: 100 + number)
        }
        let target = try rig.fixture.message(chat: 4, type: 0, text: "\(secret) is the plan", member: 1, pk: 400)
        try await rig.ingest()
        #expect(try rig.copies(of: secret) > 0, "the word is stored before the revoke")
        try rig.fixture.run("UPDATE ZWAMESSAGE SET ZMESSAGETYPE = 14, ZTEXT = NULL WHERE Z_PK = \(target)")
        rig.move(to: rig.now.addingTimeInterval(60))
        let report = try await rig.ingest()
        #expect(report.tombstones == 1 && report.erasedLines == 1)
        #expect(try rig.copies(of: secret) == 0, "no byte of the database file or its log holds the word")
        let tombstones = try rig.rows("SELECT text FROM evidence WHERE tombstone = 1")
        #expect(tombstones.count == 1 && tombstones[0].text(0) == "")
        #expect(try rig.count("SELECT count(*) FROM evidence WHERE text LIKE '%secret%'") == 0)
    }

    /// The Mac was closed for ten days. The sender deleted the message meanwhile. A revoke is found whatever the age
    /// of the message and the time since the last read.
    @Test func aRevokeIsFoundAfterALongGapAndForAnOldMessage() async throws {
        let rig = try Rig()
        let secret = "zxq\(UInt32.random(in: 100_000...999_999))secret"
        let target = try rig.fixture.message(chat: 4, type: 0, text: "\(secret) plan", member: 1, date: 1000, pk: 11)
        rig.move(to: Self.later)
        try await rig.ingest()
        try rig.fixture.run("UPDATE ZWAMESSAGE SET ZMESSAGETYPE = 14, ZTEXT = NULL WHERE Z_PK = \(target)")
        rig.move(to: Self.later.addingTimeInterval(10 * 86_400))
        let report = try await rig.ingest()
        #expect(report.tombstones == 1 && report.erasedLines == 1)
        #expect(try rig.copies(of: secret) == 0 && rig.texts().isEmpty)
    }

    @Test func anEditMadeWhileTheMacWasClosedIsStillSeen() async throws {
        let rig = try Rig()
        try rig.fixture.message(chat: 4, type: 0, text: "meet at 5", member: 1, date: 1000, pk: 11)
        try await rig.ingest()
        try rig.fixture.run("UPDATE ZWAMESSAGE SET ZTEXT = 'meet at 6' WHERE Z_PK = 11")
        rig.move(to: Self.later)
        #expect(try await rig.ingest().inserted == 1, "the window starts at the last read, not at now")
    }

    /// WhatsApp rewrote the member's id from one form to the other between the two reads: the keys differ, the chat
    /// and the stanza id do not.
    @Test func aRevokeErasesTheTextWhenTheMembersIDChangedForm() async throws {
        let rig = try Rig()
        let secret = "zxq\(UInt32.random(in: 100_000...999_999))secret"
        try rig.fixture.run("INSERT INTO ZWAGROUPMEMBER VALUES (20, 4, '777@lid', NULL, NULL, 1)")
        try rig.fixture.message(chat: 4, type: 0, text: "\(secret) plan", member: 20, stanza: "SX", pk: 11)
        try await rig.ingest()
        try rig.fixture.run("UPDATE ZWAGROUPMEMBER SET ZMEMBERJID = '777@s.whatsapp.net' WHERE Z_PK = 20")
        try rig.fixture.run("UPDATE ZWAMESSAGE SET ZMESSAGETYPE = 14, ZTEXT = NULL WHERE Z_PK = 11")
        let report = try await rig.ingest()
        #expect(report.tombstones == 1 && report.erasedLines == 1)
        #expect(try rig.copies(of: secret) == 0)
    }

    // MARK: Consent

    @Test func aChatThePolicyDoesNotAllowIsNeverQueried() async throws {
        let rig = try Rig(allowing: [selfJID])
        try rig.fixture.message(chat: 4, type: 0, text: "x", member: 1, pk: 11)
        let report = try await rig.ingest([groupJID])
        #expect(report.failures.first?.error as? ReadError == .denied(.labelNotAllowed))
        #expect(try rig.count("SELECT count(*) FROM evidence") == 0)
    }

    @Test func theReaderIsRegisteredUnderItsOldName() {
        #expect(
            SourceRegistry.descriptor(named: "whatsapp_chat")
                == WhatsAppChatReader(chatJID: groupJID, policy: whatsappOn).descriptor)
    }
}

/// The 31 type codes measured on the founder's store (research E-R3 §2) and whether any row of the type has text.
enum MeasuredWhatsAppTypes {
    static let types: [(code: Int, hasText: Bool)] = [
        (0, true), (6, true), (1, false), (7, true), (15, false), (59, false), (10, true), (2, false), (14, true),
        (8, true), (12, true), (19, false), (76, false), (42, true), (66, false), (11, false), (3, false),
        (75, false), (4, false), (20, false), (41, true), (55, false), (60, false), (43, true), (68, false),
        (25, true), (5, false), (28, false), (46, false), (13, false), (71, true),
    ]
}
