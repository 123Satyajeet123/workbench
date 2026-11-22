import Foundation
import GRDB
import Kernel
import Lines
import Synchronization
import Testing

@testable import WorkbenchCore

/// M1 step 2a, round 2: a revoke is final (review H1, H3, M3, M8), the user delete paths erase evidence (H2), one bad
/// chat does not stop the others (M1), the cursor only moves forward and a corrupt one resets (L6, L7), and old
/// citation ids are scoped by chat and mapped once (M7).
@Suite struct EvidenceFinalityTests {
    typealias World = EvidenceIngestTests.World
    static let chat = EvidenceIngestTests.chat
    static let member = EvidenceIngestTests.member

    /// The same message as another form of its author's jid (`@lid` against `@s.whatsapp.net`).
    static func message(_ text: String, stanza: String, member: String, chat: String = chat) throws -> ObservedLine {
        let key = try EntityKey.whatsAppGroup(chat: chat, author: .member(member), stanzaID: stanza)
        return ObservedLine(
            line: Line(entity: key, text: text, readerVersion: "test 1"), actor: member, messageRef: stanza)
    }

    static func revoke(stanza: String, member: String, chat: String = chat) throws -> ObservedLine {
        let key = try EntityKey.whatsAppGroup(chat: chat, author: .member(member), stanzaID: stanza)
        return ObservedLine(
            line: .tombstone(entity: key, readerVersion: "test 1"), actor: member, messageRef: stanza)
    }

    static func filler(_ count: Int) throws -> [ObservedLine] {
        try (0..<count).map { try message("common words here \($0)", stanza: "f\($0)", member: member) }
    }

    // MARK: A revoke is final

    @Test func editThenRevokeErasesEveryVersionOfTheMessage() throws {
        let world = try World()
        let first = EvidenceIngestTests.word()
        let second = EvidenceIngestTests.word()
        _ = try world.record(
            try Self.filler(300) + [try Self.message("\(first) draft", stanza: "s", member: Self.member)])
        _ = try world.record([try Self.message("\(second) final", stanza: "s", member: Self.member)])
        _ = try world.store.writer.writeWithoutTransaction { try $0.checkpoint(.truncate) }
        #expect(try world.copies(of: first) > 0 && world.copies(of: second) > 0, "both versions are stored")
        let revoked = try world.record([try Self.revoke(stanza: "s", member: Self.member)])
        #expect(revoked.erasedLines == 2 && revoked.tombstones == 1)
        #expect(try world.copies(of: first) == 0 && world.copies(of: second) == 0)
    }

    /// The author's jid changed form between the read of the text and the read of the revoke: the keys differ, the
    /// chat and the message id do not.
    @Test func aRevokeErasesByChatAndMessageIDWhateverTheAuthorForm() throws {
        let world = try World()
        let secret = EvidenceIngestTests.word()
        _ = try world.record([try Self.message("\(secret) plan", stanza: "s", member: "91@lid")])
        let revoked = try world.record([try Self.revoke(stanza: "s", member: "91@s.whatsapp.net")])
        #expect(revoked.erasedLines == 1)
        #expect(try world.copies(of: secret) == 0)
        #expect(try world.count("SELECT count(*) FROM evidence WHERE tombstone = 0") == 0)
    }

    @Test func aRevokeNeverErasesAnotherMessageOrAnotherChat() throws {
        let world = try World(allowing: [Self.chat, "120364@g.us"])
        _ = try world.record([try Self.message("keep this", stanza: "t", member: Self.member)])
        _ = try world.record(
            [try Self.message("same id, other chat", stanza: "s", member: Self.member, chat: "120364@g.us")],
            chat: "120364@g.us")
        _ = try world.record([try Self.revoke(stanza: "s", member: Self.member)])
        #expect(try world.count("SELECT count(*) FROM evidence WHERE tombstone = 0") == 2)
    }

    /// The racing read held the text and writes it after the revoke was stored: the store refuses it.
    @Test func aTextLineWrittenAfterItsRevokeIsRefusedAndStaysOut() throws {
        let world = try World()
        let secret = EvidenceIngestTests.word()
        _ = try world.record([try Self.revoke(stanza: "s", member: Self.member)])
        let late = try world.record([try Self.message("\(secret) late", stanza: "s", member: Self.member)])
        #expect(late.inserted == 0 && late.refusedAfterRevoke == 1)
        let otherForm = try world.record([try Self.message("\(secret) form", stanza: "s", member: "91@lid")])
        #expect(otherForm.refusedAfterRevoke == 1)
        #expect(try world.count("SELECT count(*) FROM evidence WHERE tombstone = 0") == 0)
        #expect(try world.copies(of: secret) == 0)
        let other = try world.record([try Self.message("another message", stanza: "t", member: Self.member)])
        #expect(other.inserted == 1 && other.refusedAfterRevoke == 0)
    }

    /// Two ingests at once: the second does not start reading before the first has written.
    @Test func ingestsRunOneAfterAnother() async throws {
        let world = try World()
        let running = Mutex(0)
        let overlap = Mutex(false)
        let source = EvidenceIngestTests.Scripted { _ in
            let now = running.withLock { count -> Int in
                count += 1
                return count
            }
            if now > 1 { overlap.withLock { $0 = true } }
            try? await Task.sleep(for: .milliseconds(50))
            running.withLock { $0 -= 1 }
            return SourceRead()
        }
        async let one = world.store.ingest(source, owner: EvidenceIngestTests.owner, now: t0)
        async let two = world.store.ingest(source, owner: EvidenceIngestTests.owner, now: t0)
        _ = try await (one, two)
        #expect(!overlap.withLock { $0 })
    }

    // MARK: The delete paths erase evidence

    @Test func deletingAKindErasesItsEvidenceAndOnlyItsEvidence() throws {
        let world = try World()
        let secret = EvidenceIngestTests.word()
        _ = try world.record(
            try Self.filler(300) + [try Self.message("\(secret) plan", stanza: "s", member: Self.member)])
        try world.store.delete(.kind(.mail, before: nil))
        #expect(try world.count("SELECT count(*) FROM evidence") == 301, "another kind leaves it")
        try world.store.delete(.kind(.whatsapp, before: nil))
        #expect(try world.count("SELECT count(*) FROM evidence") == 0)
        #expect(try world.count("SELECT count(*) FROM evidence_fts_docsize") == 0)
        #expect(try world.copies(of: secret) == 0)
        #expect(try world.cursor() == nil, "a full delete takes the cursor too")
    }

    @Test func theRetentionSweepErasesOldEvidenceAndKeepsNewAndTheCursor() throws {
        let world = try World()
        let old = EvidenceIngestTests.word()
        let new = EvidenceIngestTests.word()
        _ = try world.record([try Self.message("\(old) old", stanza: "o", member: Self.member)])
        world.advance(by: 40 * 86_400)
        _ = try world.record([try Self.message("\(new) new", stanza: "n", member: Self.member)])
        try world.store.delete(.everything(before: world.clock.now.withLock { $0 }.addingTimeInterval(-30 * 86_400)))
        #expect(try world.copies(of: old) == 0 && world.copies(of: new) > 0)
        #expect(try world.cursor() != nil)
        try world.store.delete(.everything(before: nil))
        #expect(try world.count("SELECT count(*) FROM evidence") == 0 && world.copies(of: new) == 0)
    }

    /// Derived copies of erased words are counted in the preview and left to the fact machinery (M2 F7).
    @Test func thePreviewCountsTheFactsThatCiteAnErasedLine() throws {
        let world = try World()
        try world.store.writer.write { db in
            try EvidenceIngestTests.fact(db, first: 11, last: 11, quote: "plan")
            try EvidenceIngestTests.fact(db, first: 12, last: 14, quote: "ship")
            try EvidenceIngestTests.fact(db, first: 50, last: 50, quote: "elsewhere")
            try EvidenceIngestTests.fact(db, source: "screen", first: 11, last: 11, quote: "not whatsapp")
        }
        _ = try world.record(
            [
                try EvidenceIngestTests.message("the plan", stanza: "a", legacy: 11),
                try EvidenceIngestTests.message("ship it", stanza: "b", legacy: 13),
            ])
        let erasure = EvidenceErasure.grant(kind: .whatsapp, label: Self.chat)
        #expect(try world.store.previewEvidenceErasure(erasure).citingFacts == 2)
        #expect(try world.store.eraseEvidence(erasure).citingFacts == 2)
        #expect(try world.count("SELECT count(*) FROM item") == 4, "the facts themselves stay")
    }

    // MARK: Read robustness

    @Test func oneBadChatIsReportedAndTheOthersAreWritten() async throws {
        let world = try World(allowing: [Self.chat, "120364@g.us"])
        let source = EvidenceIngestTests.Scripted { _ in
            SourceRead(
                readings: [
                    EvidenceIngestTests.reading(
                        [try! Self.message("good", stanza: "a", member: Self.member)], row: 5),
                    EvidenceIngestTests.reading(
                        [try! Self.message("denied", stanza: "b", member: Self.member, chat: "120365@g.us")], row: 5,
                        chat: "120365@g.us"),
                ],
                failures: [LabelFailure(label: "120366@g.us", error: EvidenceError.consentWithdrawn)])
        }
        let report = try await world.store.ingest(source, owner: EvidenceIngestTests.owner, now: t0)
        #expect(report.inserted == 1)
        #expect(report.failures.map(\.label).sorted() == ["120365@g.us", "120366@g.us"])
        #expect(report.failures.first { $0.label == "120365@g.us" }?.error as? EvidenceError == .consentWithdrawn)
    }

    @Test func aCursorOnlyMovesForwardThroughTheWriter() throws {
        let world = try World()
        _ = try world.record([try Self.message("one", stanza: "a", member: Self.member)], row: 100)
        _ = try world.record([try Self.message("two", stanza: "b", member: Self.member)], row: 40)
        #expect(try world.cursor()?.lastRow == 100)
        _ = try world.record([try Self.message("three", stanza: "c", member: Self.member)], row: 130)
        #expect(try world.cursor()?.lastRow == 130)
        _ = try world.record([try Self.message("four", stanza: "d", member: Self.member)], row: 7, uuid: "U2")
        #expect(try world.cursor()?.storeID == "U2" && world.cursor()?.lastRow == 7, "another store replaces it")
    }

    @Test func aCorruptCursorResetsThatChatAndIsReported() async throws {
        let world = try World(allowing: [Self.chat, "120364@g.us"])
        _ = try world.record([try Self.message("one", stanza: "a", member: Self.member)], row: 100)
        try await world.store.writer.write { db in
            try db.execute(
                sql: "UPDATE state SET value = 'not json' WHERE key = ?",
                arguments: [Store.cursorKey(grantID: "whatsapp:\(Self.chat)")])
        }
        let state = try world.store.scanState(kind: .whatsapp, label: Self.chat)
        #expect(state.cursor == nil && state.cursorWasCorrupt)
        let source = EvidenceIngestTests.Scripted { state in
            SourceRead(readings: [EvidenceIngestTests.reading([], row: state.cursor?.lastRow ?? 1)])
        }
        let report = try await world.store.ingest(source, owner: EvidenceIngestTests.owner, now: t0)
        #expect(report.resetCursors == [Self.chat] && report.failures.isEmpty)
        #expect(try world.store.scanState(kind: .whatsapp, label: Self.chat).cursorWasCorrupt == false)
    }

    // MARK: Old citation ids

    @Test func aFactOfOneChatSeesOnlyTheLinesOfThatChat() throws {
        let world = try World(allowing: [Self.chat, "120364@g.us"])
        try world.store.writer.write { db in
            try EvidenceIngestTests.fact(db, first: 11, last: 12, quote: "shipped the build")
            try db.execute(sql: "UPDATE item SET scope = ?", arguments: [Self.chat])
        }
        _ = try world.record([try EvidenceIngestTests.message("hello", stanza: "a", legacy: 11)])
        _ = try world.record(
            [try EvidenceIngestTests.message("we shipped the build", stanza: "b", legacy: 12, chat: "120364@g.us")],
            chat: "120364@g.us")
        let report = try world.store.checkLegacyWhatsAppCitations()
        #expect(report.resolved == 1 && report.quoteChecked == 0 && report.quoteNotFound == 1)
        try world.store.writer.write { try $0.execute(sql: "UPDATE item SET scope = ''") }
        #expect(try world.store.checkLegacyWhatsAppCitations().quoteChecked == 1, "no scope: every chat")
    }

    /// After an erase and a new consent, the store may be a new one: its row numbers must not become old citations.
    @Test func oldIDsAreNeverMappedAgainAfterAnEraseAndANewConsent() throws {
        let world = try World()
        _ = try world.record(
            [try EvidenceIngestTests.message("first store", stanza: "a", legacy: 11)], mapsLegacyRefs: true)
        let grant = EvidenceErasure.grant(kind: .whatsapp, label: Self.chat)
        try world.store.eraseEvidence(grant)
        let state = try world.store.scanState(kind: .whatsapp, label: Self.chat)
        #expect(state.cursor == nil && state.legacyMapped, "the erase took the cursor and kept the note")
        #expect(try world.count("SELECT count(*) FROM evidence_legacy") == 0, "the map went with the lines")
        let plan = Scan.plan(state: state, storeID: "U2", now: t0, window: 1)
        #expect(!plan.mapsLegacyRefs)
    }

    @Test func aReadThatGaveOldIDsNotesItInTheSameTransaction() throws {
        let world = try World()
        #expect(try !world.store.scanState(kind: .whatsapp, label: Self.chat).legacyMapped)
        _ = try world.record([try EvidenceIngestTests.message("x", stanza: "a")], mapsLegacyRefs: true)
        #expect(try world.store.scanState(kind: .whatsapp, label: Self.chat).legacyMapped)
    }
}
