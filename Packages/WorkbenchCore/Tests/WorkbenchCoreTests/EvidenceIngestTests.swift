import Foundation
import GRDB
import Kernel
import Lines
import Synchronization
import Testing

@testable import WorkbenchCore

/// M1 step 2a on the store side: lines and their cursor in one transaction, a re-read, a revoke, the erase path, the
/// old citations. A scripted observation stands in for the reader (the WhatsApp reader has its own tests).
@Suite struct EvidenceIngestTests {
    static let chat = "120363@g.us"
    static let owner = try! PersonID("owner-1")
    static let descriptor = SourceDescriptor.whatsAppChat
    static let member = "91@s.whatsapp.net"
    static let audience = AudienceDigest(owner: "me", members: [member])

    /// A store whose policy allows the chat, and a clock the test moves.
    struct World {
        final class Clock: Sendable {
            let now = Mutex(t0)
        }

        let store: Store
        let clock = Clock()

        init(allowing chats: [String] = [EvidenceIngestTests.chat]) throws {
            let clock = clock
            store = try Store(directory: temporaryDirectory(), clock: { clock.now.withLock { $0 } })
            try store.savePolicy(CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: Set(chats)]))
        }

        func advance(by seconds: TimeInterval) { clock.now.withLock { $0 = $0.addingTimeInterval(seconds) } }

        func record(
            _ lines: [ObservedLine], row: Int64 = 100, chat: String = EvidenceIngestTests.chat, uuid: String = "U1",
            readAt: Date? = nil, mapsLegacyRefs: Bool = false
        ) throws -> IngestReport {
            try store.record(
                SourceReading(
                    grant: grant(.whatsapp, label: chat, at: clock.now.withLock { $0 }), label: chat, container: chat,
                    audience: EvidenceIngestTests.audience,
                    lines: lines,
                    cursorAfter: ScanCursor(
                        storeID: uuid, lastRow: row, readAt: readAt ?? clock.now.withLock { $0 }),
                    mapsLegacyRefs: mapsLegacyRefs, readerVersion: "test 1"),
                of: EvidenceIngestTests.descriptor, owner: EvidenceIngestTests.owner)
        }

        func cursor(_ label: String = EvidenceIngestTests.chat) throws -> ScanCursor? {
            try store.scanState(kind: .whatsapp, label: label).cursor
        }

        func count(_ sql: String, _ arguments: StatementArguments = []) throws -> Int {
            try store.writer.read { try Int.fetchOne($0, sql: sql, arguments: arguments) ?? 0 }
        }

        /// Copies of the word's bytes in the database file and its log.
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

    static func entity(_ stanza: String, chat: String = chat) throws -> EntityKey {
        try EntityKey.whatsAppGroup(chat: chat, author: .member(member), stanzaID: stanza)
    }

    static func message(_ text: String, stanza: String, legacy: Int64? = nil, chat: String = chat) throws
        -> ObservedLine
    {
        ObservedLine(
            line: Line(entity: try entity(stanza, chat: chat), text: text, readerVersion: "test 1"),
            eventTime: UTCInstant(milliseconds: 1_795_000_000_000), actor: member,
            legacy: legacy.map { LegacyRef(space: .whatsAppRow, ref: $0) })
    }

    static func revoke(stanza: String, legacy: Int64? = nil) throws -> ObservedLine {
        ObservedLine(
            line: .tombstone(entity: try entity(stanza), readerVersion: "test 1"),
            eventTime: UTCInstant(milliseconds: 1_795_000_000_000), actor: member,
            legacy: legacy.map { LegacyRef(space: .whatsAppRow, ref: $0) })
    }

    static func word() -> String { "zxq\(UInt32.random(in: 100_000...999_999))secret" }

    // MARK: Lines and cursor in one transaction

    @Test func aReadWritesItsLinesAndItsCursorWithTheGrantAndTheAudience() throws {
        let world = try World()
        let report = try world.record(
            [try Self.message("login done", stanza: "a"), try Self.message("shipped", stanza: "b")], row: 42)
        #expect(report.inserted == 2 && report.seenAgain == 0)
        #expect(try world.cursor(Self.chat)?.lastRow == 42 && world.cursor(Self.chat)?.storeID == "U1")
        let row = try world.store.writer.read { try Row.fetchOne($0, sql: "SELECT * FROM evidence ORDER BY id") }
        let source = try Self.descriptor.sourceID(owner: Self.owner)
        #expect(row?["grant_id"] == "whatsapp:\(Self.chat)" && row?["retention_class"] == "chat")
        #expect(row?["obtained_by"] == "db" && row?["container"] == Self.chat && row?["quality"] == "stable")
        #expect((row?["audience_digest"] as Data?) == Data(Self.audience.bytes))
        #expect((row?["source_id"] as Data?) == Data(source.bytes))
        #expect((row?["label_id"] as Data?) == Data(Label(source: source).id.bytes))
    }

    static let cursorRefusal =
        "CREATE TRIGGER cursor_refused BEFORE INSERT ON state WHEN NEW.key LIKE 'cursor.%' BEGIN SELECT RAISE(ABORT, 'no cursor'); END"

    /// The cursor write fails after the lines were written: neither stays. With the cursor in a second transaction
    /// the lines would stay and the next read would find them again as new rows of a moved cursor.
    @Test func aFailureBetweenTheLinesAndTheCursorLeavesNeither() throws {
        let world = try World()
        try world.store.writer.write { try $0.execute(sql: Self.cursorRefusal) }
        #expect(throws: (any Error).self) { try world.record([try Self.message("one", stanza: "a")]) }
        #expect(try world.count("SELECT count(*) FROM evidence") == 0)
        #expect(try world.cursor(Self.chat) == nil)
        try world.store.writer.write { try $0.execute(sql: "DROP TRIGGER cursor_refused") }
        #expect(try world.record([try Self.message("one", stanza: "a")]).inserted == 1)
        #expect(try world.cursor(Self.chat) != nil)
    }

    /// A line the store refuses, after good ones: the good ones and the cursor are not written.
    @Test func aRefusedLineAfterGoodOnesWritesNothing() throws {
        let world = try World()
        var bad = try Self.message("bad", stanza: "z")
        bad.actor = ""
        #expect(throws: (any Error).self) { try world.record([try Self.message("good", stanza: "a"), bad]) }
        #expect(try world.count("SELECT count(*) FROM evidence") == 0)
        #expect(try world.cursor(Self.chat) == nil)
    }

    // MARK: A read again

    @Test func aReadAgainAddsNoRowsAndMovesLastSeenOnlyForward() throws {
        let world = try World()
        let lines = [try Self.message("login done", stanza: "a"), try Self.message("shipped", stanza: "b")]
        _ = try world.record(lines)
        func seen() throws -> [[Int64]] {
            try world.store.writer.read {
                try Row.fetchAll($0, sql: "SELECT first_seen, last_seen FROM evidence ORDER BY id").map {
                    [$0["first_seen"], $0["last_seen"]]
                }
            }
        }
        let first = try seen()
        world.advance(by: 60)
        let again = try world.record(lines)
        #expect(again.inserted == 0 && again.seenAgain == 2)
        #expect(try world.count("SELECT count(*) FROM evidence") == 2)
        #expect(try seen().map { $0[0] } == first.map { $0[0] }, "first_seen is frozen")
        #expect(try seen().map { $0[1] } == first.map { $0[1] + 60_000 }, "last_seen moved forward")
        world.advance(by: -3600)
        _ = try world.record(lines)
        #expect(try seen().map { $0[1] } == first.map { $0[1] + 60_000 }, "an earlier clock never moves it back")
    }

    @Test func aTextEditedAtTheSourceIsAnotherLineOfTheSameMessage() throws {
        let world = try World()
        _ = try world.record([try Self.message("meet at 5", stanza: "a")])
        let edited = try world.record([try Self.message("meet at 6", stanza: "a")])
        #expect(edited.inserted == 1)
        #expect(try world.count("SELECT count(DISTINCT entity_key) FROM evidence") == 1)
        #expect(try world.count("SELECT count(*) FROM evidence") == 2)
    }

    // MARK: Revoke

    /// The founder's decision: "delete for everyone" erases the stored text. The word must be in the file before the
    /// revoke and in no byte of the database file or its log after.
    @Test func aRevokeErasesTheTextFromTheLineSearchAndTheFile() throws {
        let world = try World()
        let secret = Self.word()
        _ = try world.record(
            (0..<300).map { try Self.message("common words here \($0)", stanza: "c\($0)") }
                + [try Self.message("\(secret) is the plan", stanza: "s", legacy: 7)]
                + (0..<300).map { try Self.message("more common words \($0)", stanza: "d\($0)") })
        _ = try world.store.writer.writeWithoutTransaction { try $0.checkpoint(.truncate) }
        #expect(try world.copies(of: secret) > 0, "the word is in the file before the revoke")
        let revoked = try world.record([try Self.revoke(stanza: "s")])
        #expect(revoked.tombstones == 1 && revoked.erasedLines == 1)
        #expect(try world.copies(of: secret) == 0)
        let kept = try world.store.writer.read {
            try Row.fetchAll(
                $0, sql: "SELECT text, tombstone FROM evidence WHERE entity_key = ?",
                arguments: [Data(try Self.entity("s").bytes)])
        }
        #expect(kept.count == 1 && kept[0]["tombstone"] == 1 && kept[0]["text"] == "")
        #expect(try world.store.writer.read { try EvidenceStepTests.texts(matching: secret, in: $0) } == [])
    }

    @Test func aRevokeSeenAgainChangesNothingAndTheTextDoesNotComeBack() throws {
        let world = try World()
        _ = try world.record([try Self.message("plan", stanza: "s")])
        _ = try world.record([try Self.revoke(stanza: "s")])
        let again = try world.record([try Self.revoke(stanza: "s")])
        #expect(again.tombstones == 0 && again.seenAgain == 1 && again.erasedLines == 0)
        #expect(try world.count("SELECT count(*) FROM evidence") == 1)
    }

    @Test func aMessageRevokedBeforeItWasEverReadIsOnlyATombstone() throws {
        let world = try World()
        let report = try world.record([try Self.revoke(stanza: "s")])
        #expect(report.tombstones == 1 && report.erasedLines == 0)
        #expect(try world.count("SELECT count(*) FROM evidence WHERE tombstone = 1") == 1)
    }

    @Test func aRevokeLeavesTheOtherLinesOfTheChatAlone() throws {
        let world = try World()
        _ = try world.record([try Self.message("keep me", stanza: "k"), try Self.message("drop me", stanza: "s")])
        _ = try world.record([try Self.revoke(stanza: "s")])
        #expect(try world.count("SELECT count(*) FROM evidence WHERE text = 'keep me'") == 1)
    }

    // MARK: Erase

    /// Two sources, two grants and two ages, each with its own planted word.
    struct Planted {
        let world: World
        let secrets: [String]
        let sources: [SourceID]

        init() throws {
            world = try World(allowing: ["120363@g.us", "120364@g.us"])
            secrets = (0..<4).map { _ in EvidenceIngestTests.word() }
            // chat A at t0: secret 0; chat B at t0: secret 1; chat A at t0 + 10 days: secret 2 (new line, same grant)
            _ = try world.record(
                [try EvidenceIngestTests.message("\(secrets[0]) a", stanza: "a1")], row: 10)
            _ = try world.record(
                [try EvidenceIngestTests.message("\(secrets[1]) b", stanza: "b1", chat: "120364@g.us")], row: 5,
                chat: "120364@g.us")
            world.advance(by: 10 * 86_400)
            _ = try world.record(
                [try EvidenceIngestTests.message("\(secrets[2]) a later", stanza: "a2")], row: 11)
            sources = [try EvidenceIngestTests.descriptor.sourceID(owner: EvidenceIngestTests.owner)]
        }
    }

    static func everythingStored(_ world: World) throws -> [[String]] {
        try world.store.writer.read { db in
            try ["evidence", "evidence_view", "evidence_legacy", "state"].map { table in
                try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY 1, 2").map { "\($0)" }
            }
        }
    }

    @Test func eraseByGrantRemovesThatChatAndItsCursorAndNothingElse() throws {
        let planted = try Planted()
        let world = planted.world
        let erasure = EvidenceErasure.grant(kind: .whatsapp, label: "120363@g.us")
        let before = try Self.everythingStored(world)
        let preview = try world.store.previewEvidenceErasure(erasure)
        #expect(try Self.everythingStored(world) == before, "a preview changes nothing")
        #expect(preview.lines == 2 && preview.searchEntries == 2 && preview.cursors == 1)
        #expect(try world.store.eraseEvidence(erasure) == preview)
        let copies = try planted.secrets.map { try world.copies(of: $0) }
        #expect(copies[0] == 0 && copies[2] == 0 && copies[1] > 0, "chat A is gone, chat B stays")
        #expect(try world.cursor("120363@g.us") == nil)
        #expect(try world.cursor("120364@g.us") != nil)
        #expect(try world.count("SELECT count(*) FROM evidence") == 1)
    }

    @Test func eraseBySourceRemovesEveryLineOfThatSource() throws {
        let planted = try Planted()
        let world = planted.world
        let erasure = EvidenceErasure(source: planted.sources[0])
        let preview = try world.store.previewEvidenceErasure(erasure)
        #expect(preview.lines == 3 && preview.cursors == 2)
        #expect(try world.store.eraseEvidence(erasure) == preview)
        #expect(try planted.secrets.map { try world.copies(of: $0) } == [0, 0, 0, 0])
        #expect(try world.count("SELECT count(*) FROM evidence") == 0)
        let other = try Self.descriptor.sourceID(owner: try PersonID("owner-2"))
        #expect(try world.store.previewEvidenceErasure(EvidenceErasure(source: other)) == EraseCounts())
    }

    @Test func eraseByAgeRemovesOldLinesAndKeepsCursors() throws {
        let planted = try Planted()
        let world = planted.world
        let erasure = EvidenceErasure(lastSeenBefore: t0.addingTimeInterval(5 * 86_400))
        let preview = try world.store.previewEvidenceErasure(erasure)
        #expect(preview.lines == 2 && preview.cursors == 0)
        #expect(try world.store.eraseEvidence(erasure) == preview)
        let copies = try planted.secrets.map { try world.copies(of: $0) }
        #expect(copies[0] == 0 && copies[1] == 0 && copies[2] > 0, "only the line seen 10 days later stays")
        #expect(try world.cursor("120363@g.us") != nil)
    }

    @Test func eraseFollowsViewsAndOldCitationsAndSearchEntries() throws {
        let world = try World()
        _ = try world.record([try Self.message("viewed line", stanza: "v", legacy: 9)])
        let lineID = try #require(
            try world.store.writer.read { try Data.fetchOne($0, sql: "SELECT line_id FROM evidence") })
        try world.store.writer.write {
            try $0.execute(
                sql: "INSERT INTO evidence_view(view_id, ordinal, line_id) VALUES (?, 0, ?)",
                arguments: [Data(repeating: 3, count: 32), lineID])
        }
        let erasure = EvidenceErasure.grant(kind: .whatsapp, label: Self.chat)
        #expect(
            try world.store.previewEvidenceErasure(erasure)
                == EraseCounts(lines: 1, views: 1, legacyCitations: 1, searchEntries: 1, cursors: 1))
        try world.store.eraseEvidence(erasure)
        for table in ["evidence", "evidence_view", "evidence_legacy", "evidence_fts_docsize"] {
            #expect(try world.count("SELECT count(*) FROM \(table)") == 0, "\(table)")
        }
    }

    @Test func anErasureThatNamesNothingIsRefused() throws {
        let world = try World()
        _ = try world.record([try Self.message("kept", stanza: "a")])
        #expect(throws: EvidenceError.erasureNamesNothing) { try world.store.eraseEvidence(EvidenceErasure()) }
        #expect(throws: EvidenceError.erasureNamesNothing) { try world.store.previewEvidenceErasure(EvidenceErasure()) }
        #expect(try world.count("SELECT count(*) FROM evidence") == 1)
    }

    // MARK: Consent at write time

    @Test func aRevokeBetweenTheReadAndTheWriteWritesNothing() throws {
        let world = try World()
        #expect(try world.record([try Self.message("one", stanza: "a")]).inserted == 1)
        try world.store.savePolicy(CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: []]))
        #expect(throws: EvidenceError.consentWithdrawn) { try world.record([try Self.message("two", stanza: "b")]) }
        #expect(try world.count("SELECT count(*) FROM evidence") == 1)
    }

    @Test func aGrantForAnotherChatOrAnExpiredGrantIsRefused() throws {
        let world = try World(allowing: [Self.chat, "120364@g.us"])
        var observation = SourceReading(
            grant: grant(.whatsapp, label: "120364@g.us"), label: Self.chat, container: Self.chat,
            audience: Self.audience, lines: [try Self.message("x", stanza: "a")],
            cursorAfter: ScanCursor(storeID: "U1", lastRow: 1, readAt: t0), readerVersion: "test 1")
        #expect(throws: StoreError.self) { try world.store.record(observation, of: Self.descriptor, owner: Self.owner) }
        observation.grant = grant(.whatsapp, label: Self.chat)
        world.advance(by: 301)
        #expect(throws: StoreError.grantExpired) {
            try world.store.record(observation, of: Self.descriptor, owner: Self.owner)
        }
        #expect(try world.count("SELECT count(*) FROM evidence") == 0)
    }

    // MARK: Old citations

    static func fact(_ db: Database, source: String = "whatsapp", first: Int64, last: Int64, quote: String) throws {
        if try Int.fetchOne(db, sql: "SELECT count(*) FROM run") == 0 {
            try db.execute(
                sql: """
                    INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                    VALUES ('t', 'm', 'p', 0, 's', '2026-11-19T10:00:00Z', '2026-11-19T10:00:01Z', 'done')
                    """)
        }
        try db.execute(
            sql: """
                INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                    quote, created_at) VALUES ('t', 1, '2026-11-19', '', ?, ?, ?, '2026-11-19T10:00:00Z',
                    '2026-11-19T11:00:00Z', '{}', ?, '2026-11-19T12:00:00Z')
                """, arguments: [source, first, last, quote])
    }

    @Test func oldWhatsAppCitationsResolveThroughOneMapAndTheirQuotesAreChecked() throws {
        let world = try World()
        try world.store.writer.write { db in
            try Self.fact(db, first: 11, last: 11, quote: "shipped the build")  // mapped, quote in the line
            try Self.fact(db, first: 12, last: 14, quote: "ship the build")  // a range; the quote is in row 13
            try Self.fact(db, first: 11, last: 11, quote: "something else entirely")  // mapped, quote not in line
            try Self.fact(db, first: 15, last: 15, quote: "the plan")  // row 15 was revoked
            try Self.fact(db, first: 99, last: 99, quote: "never seen")  // no such row
            try Self.fact(db, source: "screen", first: 3, last: 3, quote: "not whatsapp")
        }
        let ids = "SELECT id, cite_first, cite_last FROM item ORDER BY id"
        let before = try world.store.writer.read { try Row.fetchAll($0, sql: ids) }
        _ = try world.record(
            [
                try Self.message("We shipped the build today", stanza: "m11", legacy: 11),
                try Self.message("hello", stanza: "m12", legacy: 12),
                try Self.message("please ship the build by five", stanza: "m13", legacy: 13),
                try Self.revoke(stanza: "m15", legacy: 15),
            ])
        let report = try world.store.checkLegacyWhatsAppCitations()
        #expect(
            report
                == LegacyCitationReport(
                    facts: 5, resolved: 4, quoteChecked: 2, quoteNotFound: 1, revoked: 1, unresolved: 1, refs: 5,
                    refsUnresolved: 2))
        let after = try world.store.writer.read { try Row.fetchAll($0, sql: ids) }
        #expect(before == after, "no item id, cite_first or cite_last changed")
        #expect(try world.count("SELECT count(*) FROM item") == 6, "nothing was deleted")
    }

    /// A message that was read, cited, and later revoked: its old citation now points at the tombstone, so it
    /// reports "revoked", not "unresolved".
    @Test func aCitationOfAMessageRevokedLaterPointsAtItsTombstone() throws {
        let world = try World()
        try world.store.writer.write { try Self.fact($0, first: 21, last: 21, quote: "the plan") }
        _ = try world.record([try Self.message("the plan is X", stanza: "s", legacy: 21)])
        #expect(try world.store.checkLegacyWhatsAppCitations().quoteChecked == 1)
        _ = try world.record([try Self.revoke(stanza: "s")])
        let report = try world.store.checkLegacyWhatsAppCitations()
        #expect(report.revoked == 1 && report.unresolved == 0 && report.quoteChecked == 0)
    }

    @Test func theFirstLineToTakeAnOldIDKeepsIt() throws {
        let world = try World()
        _ = try world.record([try Self.message("meet at 5", stanza: "a", legacy: 31)])
        _ = try world.record([try Self.message("meet at 6", stanza: "a", legacy: 31)])
        let text = try world.store.writer.read {
            try String.fetchOne(
                $0,
                sql: """
                    SELECT text FROM evidence_legacy JOIN evidence ON evidence.line_id = evidence_legacy.line_id
                    WHERE ref = 31
                    """)
        }
        #expect(text == "meet at 5")
    }

    // MARK: Indexes

    static func plan(_ world: World, _ sql: String, _ arguments: StatementArguments) throws -> String {
        try world.store.writer.read { db in
            try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + sql, arguments: arguments)
                .map { $0["detail"] as String }.joined(separator: " | ")
        }
    }

    @Test func theEraseAndRevokeQueriesUseTheirIndexes() throws {
        let world = try World()
        let plans = try [
            ("evidence_entity", "DELETE FROM evidence WHERE entity_key = ? AND tombstone = 0", [Data([1])]),
            ("evidence_source", "SELECT count(*) FROM evidence WHERE source_id = ? AND last_seen < ?", [Data([1]), 1]),
        ].map { (index: $0.0, plan: try Self.plan(world, $0.1, StatementArguments($0.2))) }
        for (index, plan) in plans { #expect(plan.contains("INDEX \(index)"), Comment(rawValue: "\(index): \(plan)")) }
        let grantPlan = try world.store.writer.read { db in
            try Row.fetchAll(
                db, sql: "EXPLAIN QUERY PLAN SELECT count(*) FROM evidence WHERE grant_id = ? AND last_seen < ?",
                arguments: ["whatsapp:x", 1]
            ).map { $0["detail"] as String }.joined()
        }
        #expect(grantPlan.contains("evidence_grant"), Comment(rawValue: grantPlan))
        let withoutIndex = try EvidenceStepTests.database(rewriting: {
            $0.hasPrefix("CREATE INDEX evidence_entity") ? nil : $0
        })
        let without = try withoutIndex.read {
            try Row.fetchAll(
                $0, sql: "EXPLAIN QUERY PLAN DELETE FROM evidence WHERE entity_key = ? AND tombstone = 0",
                arguments: [Data([1])]
            ).map { $0["detail"] as String }.joined()
        }
        #expect(without.contains("SCAN"), Comment(rawValue: "without its index the revoke delete scans: \(without)"))
    }

    // MARK: Registry

    @Test func aSourceIsFoundByItsKeyOrByTheOldEnumValueAndOnlyNamedSourcesStart() {
        #expect(SourceRegistry.descriptor(named: "whatsapp.chat") == .whatsAppChat)
        #expect(SourceRegistry.descriptor(named: HelperSpec.Source.whatsappChat.rawValue) == .whatsAppChat)
        #expect(SourceRegistry.descriptor(named: "nonsense") == nil)
        #expect(
            SourceRegistry.demanded(by: ["whatsapp_chat", "whatsapp.chat", "screen_sessions"]) == [
                .whatsAppChat, .screenWindow,
            ])
        #expect(SourceRegistry.demanded(by: [String]()).isEmpty, "a source no machine names never starts")
    }

    @Test func everyOldSourceNameIsPortedOrListedAsNot() {
        let notPorted: Set<HelperSpec.Source> = [.news, .webSearch]
        for source in HelperSpec.Source.allCases {
            #expect((SourceRegistry.descriptor(named: source.rawValue) == nil) == notPorted.contains(source))
        }
        #expect(HelperSpec.Source.whatsappChat.lines == SourceDescriptor.whatsAppChat.grammar)
        #expect(SourceDescriptor.whatsAppChat.consent == HelperSpec.Source.whatsappChat.kind)
    }

    @Test func aSourceIDBelongsToItsOwner() throws {
        let mine = try Self.descriptor.sourceID(owner: Self.owner)
        #expect(mine == (try Self.descriptor.sourceID(owner: Self.owner)))
        #expect(mine != (try Self.descriptor.sourceID(owner: try PersonID("owner-2"))))
    }

    // MARK: Ingest

    struct Scripted: EvidenceSource {
        let descriptor = SourceDescriptor.whatsAppChat
        let build: @Sendable (ScanState) async -> SourceRead

        func observe(state: @Sendable (String) throws -> ScanState, now: Date) async throws -> SourceRead {
            await build(try state(EvidenceIngestTests.chat))
        }

        func sightings(policy: CapturePolicy, now: Date) -> [ContainerSighting] { [] }
    }

    static func reading(_ lines: [ObservedLine], row: Int64, chat: String = chat) -> SourceReading {
        SourceReading(
            grant: grant(.whatsapp, label: chat), label: chat, container: chat, audience: audience, lines: lines,
            cursorAfter: ScanCursor(storeID: "U1", lastRow: row, readAt: t0), readerVersion: "test 1")
    }

    @Test func ingestGivesTheSourceTheStoredStateAndWritesWhatItSaw() async throws {
        let world = try World()
        let seen = Mutex<[ScanCursor?]>([])
        let source = Scripted { state in
            seen.withLock { $0.append(state.cursor) }
            return SourceRead(readings: [Self.reading([try! Self.message("one", stanza: "a")], row: 9)])
        }
        let first = try await world.store.ingest(source, owner: Self.owner, now: t0)
        let second = try await world.store.ingest(source, owner: Self.owner, now: t0)
        #expect(first.inserted == 1 && second.inserted == 0 && second.seenAgain == 1)
        #expect(seen.withLock { $0 } == [nil, ScanCursor(storeID: "U1", lastRow: 9, readAt: t0)])
    }
}
