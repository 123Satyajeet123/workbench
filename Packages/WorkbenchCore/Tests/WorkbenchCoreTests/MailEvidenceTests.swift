import Foundation
import GRDB
import Kernel
import Lines
import Synchronization
import Testing

@testable import WorkbenchCore

/// ADR-017 step 2: mail and deck lines are evidence lines, written once through the EvidenceWriter with the consent
/// checked in the transaction, a label from the grant, an audience from the page's addresses, and an erase path.
@Suite struct MailEvidenceTests {
    static let owner = try! PersonID("owner-1")
    static let ownerResult = Result<PersonID, any Error>.success(owner)
    static let named = CapturePolicy(switches: [.mail: true, .web: true], allowList: [.mail: ["Deals"]]).withTestBrowser
    static let gmail = MailContext(
        browser: "com.brave.Browser", url: "https://mail.google.com/mail/u/0/#label/Deals/FMfcgz", label: "Deals",
        threadId: "FMfcgz", messageId: "msg-1")

    static func message(
        sender: String = "ana@acme.example", recipients: [String] = ["vc@fund.example", "raj@acme.example"],
        account: String? = "vc@fund.example", text: String = "Acme raised $20 million in its seed round.",
        messageId: String = "msg-1"
    ) -> MailMessage {
        var context = gmail
        context.messageId = messageId
        return MailMessage(
            context: context, sender: sender, recipients: recipients, account: account, sent: 1_789_990_000, text: text)
    }

    func store(_ policy: CapturePolicy? = named) throws -> Store {
        let store = try makeStore()
        if let policy { try store.savePolicy(policy) }
        return store
    }

    func keep(_ message: MailMessage, in store: Store) throws -> PageHost.Reply {
        var message = message
        message.context.browser = "com.brave.Browser"
        return try MailIntake.keep(message, store: store, owner: Self.owner)
    }

    func count(_ sql: String, in store: Store, _ arguments: StatementArguments = []) throws -> Int {
        try store.writer.read { try Int.fetchOne($0, sql: sql, arguments: arguments) ?? 0 }
    }

    func row(in store: Store) throws -> Row {
        try #require(try store.writer.read { try Row.fetchOne($0, sql: "SELECT * FROM evidence ORDER BY id") })
    }

    /// Copies of the word's bytes in the database file and its log.
    func copies(of word: String, in store: Store) throws -> Int {
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

    // MARK: Consent in the transaction

    @Test func aMailLineIsNotWrittenWhenTheConsentIsGoneInsideTheTransaction() throws {
        let store = try store()
        let reading = try #require(
            Self.message().reading(grant: grant(.mail, label: "Deals"), now: t0))
        try store.savePolicy(CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Personal"]]).withTestBrowser)
        #expect(throws: EvidenceError.consentWithdrawn) {
            try store.record(reading, of: .gmailMail, owner: Self.owner)
        }
        #expect(try count("SELECT count(*) FROM evidence", in: store) == 0)
        try store.savePolicy(Self.named)
        #expect(try store.record(reading, of: .gmailMail, owner: Self.owner).inserted == 1)
    }

    // MARK: Label from the grant

    @Test func aMailLinesLabelIsThatOfItsSourceAndItsGrantNamesTheLabel() throws {
        let store = try store()
        #expect(try keep(Self.message(), in: store).kept)
        let line = try row(in: store)
        let source = try SourceDescriptor.gmailMail.sourceID(owner: Self.owner)
        #expect((line["label_id"] as Data?) == Data(Label(source: source).id.bytes))
        #expect((line["source_id"] as Data?) == Data(source.bytes))
        #expect(line["grant_id"] == "mail:Deals" && line["retention_class"] == "mail")
        #expect(line["obtained_by"] == "dom_text" && line["container"] == "FMfcgz" && line["quality"] == "stable")
        let part = try #require(try store.queries.mailParts(from: .distantPast, to: .distantFuture).first)
        #expect(part.provenance?.label == Label(source: source) && part.label == "Deals")
    }

    @Test func aGrantWithNoLabelGivesNoLine() throws {
        #expect(Self.message().reading(grant: grant(.mail, label: ""), now: t0) == nil)
        let named = try #require(Self.message().reading(grant: grant(.mail, label: "Deals"), now: t0))
        #expect(named.label == "Deals", "the label is the grant's")
    }

    // MARK: Audience from the participants, failing closed

    @Test func aMailLinesAudienceIsTheOwnerTheSenderAndEveryoneItWentTo() throws {
        let store = try store()
        _ = try keep(Self.message(recipients: ["VC@Fund.example", " raj@acme.example"]), in: store)
        let expected = AudienceDigest(
            owner: "me", members: ["ana@acme.example", "vc@fund.example", "raj@acme.example"])
        #expect((try row(in: store)["audience_digest"] as Data?) == Data(expected.bytes))
    }

    @Test func aMessageWithNoRecipientOrNoSenderGivesNoLine() throws {
        let store = try store()
        for message in [Self.message(recipients: []), Self.message(sender: "  "), Self.message(recipients: [" "])] {
            #expect(try keep(message, in: store) == PageHost.Reply(kept: false))
        }
        #expect(try count("SELECT count(*) FROM evidence", in: store) == 0)
        #expect(try store.queries.mailParts(from: .distantPast, to: .distantFuture).isEmpty)
    }

    // MARK: Actor and authority

    @Test func theActorIsMeForTheAccountAddressTheAddressForOthersAndNothingIsGuessed() throws {
        #expect(
            MailPeople(sender: "VC@fund.example", recipients: ["a@b.example"], account: "vc@Fund.example").actor == "me"
        )
        #expect(
            MailPeople(sender: "ana@acme.example", recipients: [], account: "vc@fund.example").actor
                == "ana@acme.example")
        #expect(MailPeople(sender: "ana@acme.example", recipients: [], account: nil).actor == "ana@acme.example")
        #expect(MailPeople(sender: "", recipients: [], account: "vc@fund.example").actor == nil)
    }

    @Test func theAuthorityOfAMailLineFollowsItsSender() throws {
        let store = try store()
        _ = try keep(Self.message(sender: "vc@fund.example", messageId: "mine"), in: store)
        _ = try keep(Self.message(sender: "ana@acme.example", messageId: "theirs"), in: store)
        _ = try keep(Self.message(sender: "ana@acme.example", account: nil, messageId: "no-account"), in: store)
        let parts = try store.queries.mailParts(from: .distantPast, to: .distantFuture)
        #expect(parts.map(\.sender) == ["me", "ana@acme.example", "ana@acme.example"])
        #expect(parts.map { $0.provenance?.authority } == [.ownWords, .groupMember, .groupMember])
    }

    // MARK: Quoted and forwarded words

    private func quotedMessage(text: String, quoted: String?, messageId: String = "msg-q") -> MailMessage {
        var message = Self.message(text: text, messageId: messageId)
        message.quoted = quoted
        return message
    }

    @Test func aQuotedBlockIsItsOwnLineMarkedForwardedWithTheLowestAuthority() throws {
        let store = try store()
        _ = try keep(quotedMessage(text: "Yes, send it.", quoted: "We raised $20 million."), in: store)
        let flags = try store.writer.read {
            try Row.fetchAll($0, sql: "SELECT text, forwarded FROM evidence ORDER BY id").map {
                ($0["text"] as String, $0["forwarded"] as Int)
            }
        }
        #expect(flags.map(\.0) == ["Yes, send it.", "We raised $20 million."] && flags.map(\.1) == [0, 1])
        let parts = try store.queries.mailParts(from: .distantPast, to: .distantFuture)
        #expect(parts.map { $0.provenance?.authority } == [.groupMember, .forwardedOrQuoted])
        #expect(
            parts.map { $0.evidence?.line } == [
                "ana@acme.example: Yes, send it.", "ana@acme.example (quoted): We raised $20 million.",
            ])
    }

    @Test func aClaimFromAReadingThatHoldsQuotedWordsIsNoMoreTrustedThanTheQuote() throws {
        let store = try store()
        _ = try keep(quotedMessage(text: "Yes, send it.", quoted: "We raised $20 million."), in: store)
        let lines = try store.queries.mailParts(from: .distantPast, to: .distantFuture).compactMap(\.evidence)
        let standing = Standing(citing: [lines[0]], facts: [], window: lines)
        #expect(standing.authority == .forwardedOrQuoted)
        #expect(standing.label != nil, "the label is still known")
    }

    @Test func aMessageOfOnlyQuotedWordsGivesOnlyTheQuotedLineAndOneWithNoneGivesNoLine() throws {
        let store = try store()
        _ = try keep(quotedMessage(text: "", quoted: "Forwarded words", messageId: "only-quote"), in: store)
        #expect(try count("SELECT count(*) FROM evidence WHERE forwarded = 1", in: store) == 1)
        #expect(try count("SELECT count(*) FROM evidence WHERE forwarded = 0", in: store) == 0)
        #expect(
            try keep(quotedMessage(text: "", quoted: nil, messageId: "empty"), in: store) == PageHost.Reply(kept: false)
        )
        #expect(
            try keep(quotedMessage(text: "", quoted: "", messageId: "empty"), in: store) == PageHost.Reply(kept: false))
    }

    @Test func aMessageWithNoQuotedBlockStaysAtTheSendersAuthority() throws {
        let store = try store()
        _ = try keep(quotedMessage(text: "Plain words.", quoted: nil), in: store)
        let parts = try store.queries.mailParts(from: .distantPast, to: .distantFuture)
        #expect(parts.map { $0.provenance?.authority } == [.groupMember] && parts.allSatisfy { !$0.isQuoted })
    }

    // MARK: Erase

    private func readingWithClaim(_ store: Store, word: String) async throws -> (run: RunID, item: Int64) {
        _ = try keep(Self.message(text: "Acme raised $20 million. \(word)"), in: store)
        let lines = try store.queries.mailParts(from: .distantPast, to: .distantFuture).compactMap(\.evidence)
        let reply =
            #"{"claims":[{"line":\#(lines[0].id),"text":"Raised $20 million.","type":"funding","value":"$20 million","quote":"raised $20 million"}]}"#
        let found = try await ClaimExtractor(
            model: RecordedModel(ScriptedModel(reply), store: store), types: fundClaimTypes
        )
        .extract(deal: "d1", lines: lines)
        let run = try #require(found.run)
        let ids = try store.saveClaims(found.claims, run: run, grant: grant(.mail, label: "Deals"))
        return (run, ids[0])
    }

    @Test func removingTheLabelErasesTheLinesTheirWordsAndTheirCopies() async throws {
        let store = try store()
        let word = "zxq\(UInt32.random(in: 100_000...999_999))secret"
        let made = try await readingWithClaim(store, word: word)
        #expect(try copies(of: word, in: store) > 0)
        let withdrawn = Self.named.withdrawn(
            .mail, in: CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Other"]]))
        #expect(withdrawn == ["Deals"])
        let counts = try store.eraseEvidence(.grant(kind: .mail, label: "Deals"))
        #expect(counts.lines == 1)
        #expect(try count("SELECT count(*) FROM evidence", in: store) == 0)
        #expect(
            try count("SELECT count(*) FROM run_text WHERE run_id = ?", in: store, [made.run]) == 0, "run text copy")
        #expect(
            try count(
                "SELECT count(*) FROM item WHERE id = ? AND source_deleted = 1 AND quote = ''", in: store, [made.item])
                == 1)
        #expect(try copies(of: word, in: store) == 0)
    }

    @Test func theSettingsDeleteOfMailErasesTheLinesAndTheirWords() async throws {
        let store = try store()
        let word = "zxq\(UInt32.random(in: 100_000...999_999))secret"
        _ = try await readingWithClaim(store, word: word)
        try store.delete(.kind(.mail, before: nil))
        #expect(try count("SELECT count(*) FROM evidence", in: store) == 0)
        #expect(try copies(of: word, in: store) == 0)
    }

    // MARK: One reading path

    @Test func aClaimReadingRecordsItsWindowAndTheItemResolvesToItsThread() async throws {
        let store = try store()
        let made = try await readingWithClaim(store, word: "plain")
        #expect(try count("SELECT count(*) FROM run_window WHERE run_id = ?", in: store, [made.run]) == 1)
        let thread = try store.queries.threadParts(ofItem: made.item)
        #expect(thread.map(\.threadID) == ["FMfcgz"] && thread.first?.provenance != nil)
    }

    @Test func aDeckPageIsAStoredLineUnderItsMessageWithTheMessagesAudience() throws {
        let store = try store()
        _ = try keep(Self.message(text: "see deck"), in: store)
        let found = try #require(try store.queries.mailMessage(thread: "FMfcgz", message: "msg-1"))
        let reading = try #require(
            found.reading(
                pages: [(1, "Slide one"), (2, "Slide two")], file: "Deck.pdf", thread: "FMfcgz", message: "msg-1",
                grant: grant(.mail, label: "Deals")))
        #expect(try store.record(reading, of: .gmailMail, owner: Self.owner).inserted == 2)
        let parts = try store.queries.mailParts(from: .distantPast, to: .distantFuture).filter(\.isDeck)
        #expect(parts.map(\.page) == [1, 2] && parts.allSatisfy { $0.name == "Deck.pdf" })
        let audiences = try store.writer.read {
            try Data.fetchAll($0, sql: "SELECT DISTINCT audience_digest FROM evidence")
        }
        #expect(audiences.count == 1, "the pages and the message share one audience")
        #expect(try store.queries.deckNames(ofMessage: "msg-1") == ["Deck.pdf"])
    }

    // MARK: Old rows

    private func oldRow(
        _ store: Store, id: Int64, label: String = "Deals", sender: String = "Ana <ana@acme.example>",
        file: String = "",
        page: Int = 0, message: String = "old-1", text: String = "Old words"
    ) throws {
        try store.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO mail_part(id, thread_id, message_id, kind, name, page, label, sender, subject, sent_at,
                        seen_at, text) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                    """,
                arguments: [
                    id, "T-old", message, page == 0 ? "message" : "deck", file, page, label, sender, "Subject",
                    t0.stored, t0.stored, text,
                ])
        }
    }

    @Test func theDryRunCountsWhatABackfillWritesAndRefuses() throws {
        let store = try store()
        try oldRow(store, id: 1)
        try oldRow(store, id: 2, sender: "", message: "old-2")
        try oldRow(store, id: 3, file: "Deck.pdf", page: 1, text: "Slide")
        try oldRow(store, id: 4, label: "Personal", message: "old-4")
        let counts = try store.previewMailBackfill()
        #expect(
            counts
                == MailBackfillCounts(
                    parts: 4, written: 3, messages: 2, deckPages: 1, senderKnown: 2, senderUnknown: 1,
                    refusedLabelNotAllowed: 1, refusedNoKey: 0))
        #expect(try count("SELECT count(*) FROM evidence", in: store) == 0, "a dry run changes nothing")
        #expect(try count("SELECT count(*) FROM mail_part", in: store) == 4)
    }

    @Test func aBackfillPlansNoWriteForALabelTheConsentDoesNotName() throws {
        let rows = [
            OldMailPart(
                id: 1, threadID: "T", messageID: "m", file: "", page: 0, label: "Deals", sender: "a@b.example",
                sentAt: t0, text: "kept"),
            OldMailPart(
                id: 2, threadID: "T", messageID: "n", file: "", page: 0, label: "Personal", sender: "a@b.example",
                sentAt: t0, text: "refused"),
        ]
        let moves = MailBackfill.moves(of: rows, allowed: ["Deals"])
        #expect(moves.map(\.label) == ["Deals"] && moves.flatMap(\.partIDs) == [1])
        #expect(MailBackfill.moves(of: rows, allowed: []).isEmpty)
    }

    @Test func theDryRunOnACopyCountsTheCopyAndLeavesTheStoreAlone() throws {
        let store = try store()
        try oldRow(store, id: 1)
        try oldRow(store, id: 2, label: "Personal", message: "old-2")
        let counts = try MailBackfillCounts.preview(onCopyOf: store.directory)
        #expect(counts.parts == 2 && counts.written == 1 && counts.refusedLabelNotAllowed == 1)
        #expect(try count("SELECT count(*) FROM mail_part", in: store) == 2)
    }

    @Test func aBackfillMovesTheAllowedRowsAsEvidenceWithTheNarrowestAudienceAndMapsTheirOldIds() throws {
        let store = try store()
        try oldRow(store, id: 7)
        try oldRow(store, id: 8, sender: "", message: "old-2", text: "No sender")
        try oldRow(store, id: 9, label: "Personal", message: "old-4")
        let counts = try store.moveMailPartsToEvidence(owner: Self.owner)
        #expect(counts.written == 2 && counts.refusedLabelNotAllowed == 1)
        let parts = try store.queries.mailParts(from: .distantPast, to: .distantFuture)
        #expect(parts.map(\.text) == ["Old words", "No sender"])
        #expect(parts.map { $0.provenance?.authority } == [.groupMember, .unknown], "the account is not known")
        let narrow = AudienceDigest(owner: "me", members: ["ana@acme.example"])
        let digests = try store.writer.read {
            try Data.fetchAll($0, sql: "SELECT audience_digest FROM evidence ORDER BY id")
        }
        #expect(digests == [Data(narrow.bytes), Data(AudienceDigest(owner: "me", members: [String]()).bytes)])
        #expect(
            try count("SELECT count(*) FROM evidence_legacy WHERE space = 'mail_part' AND ref IN (7, 8)", in: store)
                == 2)
        #expect(try count("SELECT id FROM mail_part", in: store) == 9, "the refused row stays; the moved rows are gone")
        #expect(try store.moveMailPartsToEvidence(owner: Self.owner).written == 0, "a second run has nothing to move")
        #expect(try count("SELECT count(*) FROM evidence", in: store) == 2)
    }

    @Test func anOldItemFindsItsThreadThroughTheOldCitationId() throws {
        let store = try store()
        try oldRow(store, id: 7)
        _ = try store.moveMailPartsToEvidence(owner: Self.owner)
        let run = try store.beginRun(task: "t", model: "m", prompt: "p", input: "i", kinds: [.mail])
        let item = try store.writer.write { db -> Int64 in
            try db.execute(
                sql: """
                    INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
                        created_at) VALUES ('t', ?, '2026-09-21', '', 'mail', 7, 7, ?, ?, '{}', 'q', ?)
                    """, arguments: [run, t0.stored, t0.stored, t0.stored])
            return db.lastInsertedRowID
        }
        #expect(try store.queries.threadParts(ofItem: item).map(\.text) == ["Old words"])
    }

    // MARK: Claim checks

    private func claimChecker(_ store: Store, search: FakeSearch) throws -> ClaimChecker {
        let session = try WebSession.fake(store: store, search: search, pages: FakePages())
        let model = SequencedModel([
            #"{"queries":["Acme seed round"]}"#, #"{"verdict":"not_found","page":0,"quote":""}"#,
        ])
        return ClaimChecker(model: RecordedModel(model, store: store), session: session, types: fundClaimTypes)
    }

    private func extractedClaim(_ store: Store, lines: [Evidence]) async throws -> Claim {
        let reply =
            #"{"claims":[{"line":\#(lines[0].id),"text":"Raised $20 million.","type":"funding","value":"$20 million","quote":"raised $20 million"}]}"#
        let found = try await ClaimExtractor(
            model: RecordedModel(ScriptedModel(reply), store: store), types: fundClaimTypes
        )
        .extract(deal: "d1", lines: lines)
        return try #require(found.claims.first)
    }

    @Test func aDeckClaimFromLinesWithAKnownLabelHasThatLabelAndItsQueryLeaves() async throws {
        let store = try store()
        _ = try keep(Self.message(), in: store)
        let lines = try store.queries.mailParts(from: .distantPast, to: .distantFuture).compactMap(\.evidence)
        let claim = try await extractedClaim(store, lines: lines)
        let source = try SourceDescriptor.gmailMail.sourceID(owner: Self.owner)
        #expect(claim.label == Label(source: source), "the claim's label is the join of its lines' labels")
        let search = FakeSearch(hits: [])
        _ = try await claimChecker(store, search: search).check(claim, company: "Acme")
        #expect(search.queries.withLock { $0 } == ["Acme seed round"])
    }

    @Test func aLineWithNoStoredLabelOrNoParticipantsLeavesNoQueryOut() async throws {
        let store = try store()
        _ = try keep(Self.message(recipients: []), in: store)
        #expect(try store.queries.mailParts(from: .distantPast, to: .distantFuture).isEmpty, "no participants, no line")

        let unlabelled = Evidence(
            id: 5, start: t0, line: "a: Acme raised $20 million.", quotable: ["Acme raised $20 million."])
        let claim = try await extractedClaim(store, lines: [unlabelled])
        #expect(claim.label == nil)
        let search = FakeSearch(hits: [])
        await #expect(throws: WebBlock.labelUnknown) {
            _ = try await claimChecker(store, search: search).check(claim, company: "Acme")
        }
        #expect(search.queries.withLock { $0 }.isEmpty, "the query did not leave")
    }
}
