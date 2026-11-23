import Foundation
import GRDB
import Lines
import Testing

@testable import WorkbenchCore

/// The evidence step (ADR-015). Each guard is checked on the step as written and, where a wrong step is easy to
/// write, on that wrong step too, inside `withKnownIssue`: the check must fail there.
@Suite struct EvidenceStepTests {
    /// The steps before the evidence step, then the evidence step with each statement passed through `rewrite`
    /// (nil drops it): the way to write a planted break into the schema.
    static func database(rewriting rewrite: (String) -> String? = { $0 }) throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            for statement in Schema.steps.prefix(while: { $0 != Schema.evidence }).joined() {
                try db.execute(sql: statement)
            }
            for statement in Schema.evidence.compactMap(rewrite) { try db.execute(sql: statement) }
        }
        return queue
    }

    static func line(_ text: String, chat: String = "120363@g.us", stanza: String? = nil) throws -> Line {
        let key = try EntityKey.whatsAppGroup(
            chat: chat, author: .member("91@s.whatsapp.net"), stanzaID: stanza ?? text)
        return Line(entity: key, text: text, readerVersion: "wa 1")
    }

    /// Writes one line as a reader would and returns its row id.
    @discardableResult
    static func insert(_ line: Line, into db: Database, seenAt seen: Int64 = 1_795_305_600_000) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO evidence(line_id, entity_key, quality, source_id, container, event_time, first_seen,
                    last_seen, actor, text, tombstone, label_id, grant_id, audience_digest, retention_class, obtained_by,
                    reader_version)
                VALUES (?, ?, 'stable', ?, '120363@g.us', ?, ?, ?, '91@s', ?, ?, ?, 'consent-7', ?, 'chat', 'db', ?)
                """,
            arguments: [
                Data(line.id.bytes), Data(line.entity.bytes), Data(repeating: 1, count: 16), seen, seen, seen,
                line.text, line.isTombstone ? 1 : 0, Data(repeating: 2, count: 16),
                Data(AudienceDigest(owner: "me", members: ["91@s.whatsapp.net"]).bytes), line.readerVersion,
            ])
        return db.lastInsertedRowID
    }

    static func texts(matching query: String, in db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: """
                SELECT evidence.text FROM evidence_fts JOIN evidence ON evidence.rowid = evidence_fts.rowid
                WHERE evidence_fts MATCH ? ORDER BY evidence.rowid
                """, arguments: [query.precomposedStringWithCanonicalMapping])
    }

    @Test func anEmptyStoreGetsStrictEvidenceTables() throws {
        let store = try makeStore()
        let strict = try store.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_list").filter {
                ["evidence", "evidence_view", "evidence_legacy", "evidence_fts"].contains($0["name"] as String)
            }
            .reduce(into: [String: Int]()) { $0[$1["name"]] = $1["strict"] }
        }
        #expect(strict == ["evidence": 1, "evidence_view": 1, "evidence_legacy": 1, "evidence_fts": 0])
    }

    // MARK: Migration from the previous chain

    /// A store as the shipped app left it before this step, with citations in every legacy id space.
    static func storeBeforeEvidence() throws -> URL {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        let previous = Schema.steps.prefix(while: { $0 != Schema.evidence })
        try queue.write { db in
            for statement in previous.joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = \(previous.count)")
            try db.execute(
                sql: """
                    INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                    VALUES ('t', 'm', 'p', 0, 's', '2026-11-19T10:00:00Z', '2026-11-19T10:00:01Z', 'done')
                    """)
            for (source, first, last) in [("whatsapp", 120, 124), ("screen", 7, 9), ("mail", 3, 3)] {
                try db.execute(
                    sql: """
                        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at,
                            fields, quote, created_at) VALUES ('t', 1, '2026-11-19', '', ?, ?, ?,
                            '2026-11-19T10:00:00Z', '2026-11-19T11:00:00Z', '{}', 'q', '2026-11-19T12:00:00Z')
                        """, arguments: [source, first, last])
            }
            try db.execute(sql: "DELETE FROM item WHERE id = 2")
            try db.execute(
                sql: """
                    INSERT INTO item_event(item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor)
                    VALUES (1, 'close', 'kept', 122, 'done', '2026-11-19T13:00:00Z', '2026-11-19T13:00:00Z', 1, 'model')
                    """)
            try db.execute(
                sql: """
                    INSERT INTO activity(ts, kind, app, bundle_id, title, document, text)
                    VALUES ('2026-11-19T10:00:00Z', 'text', 'Safari', 'com.apple.Safari', 'Notes', NULL, 'a page')
                    """)
            try db.execute(
                sql: """
                    INSERT INTO mail_part(thread_id, message_id, kind, name, page, label, sender, subject, sent_at,
                        seen_at, text) VALUES ('th', 'msg-f:1', 'message', '', 0, 'Deals', 'a@b', 's',
                        '2026-11-19T10:00:00Z', '2026-11-19T10:00:00Z', 'hello')
                    """)
        }
        return folder
    }

    static func legacyIDs(_ db: Database) throws -> [[Int64]] {
        try [
            "SELECT id, cite_first, cite_last FROM item ORDER BY id", "SELECT id, line_id FROM item_event ORDER BY id",
            "SELECT id FROM activity ORDER BY id", "SELECT id FROM mail_part ORDER BY id",
        ].map { sql in
            try Row.fetchAll(db, sql: sql).flatMap { row in row.databaseValues.compactMap(Int64.fromDatabaseValue) }
        }
    }

    @Test func aStoreFromThePreviousChainKeepsEveryLegacyIDAndGainsTheEvidenceTables() throws {
        let folder = try Self.storeBeforeEvidence()
        let before = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path).read(Self.legacyIDs)
        let store = try Store(directory: folder)
        let (after, version, dangling, empty) = try store.writer.read { db in
            (
                try Self.legacyIDs(db), try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try Row.fetchAll(db, sql: "PRAGMA foreign_key_check"),
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM evidence")
            )
        }
        #expect(before == [[1, 120, 124, 3, 3, 3], [1, 122], [1], [1]])
        #expect(after == before)
        #expect(version == Schema.steps.count && dangling.isEmpty && empty == 0)
    }

    // MARK: Search

    /// A Devanagari word is one token: the word is found, a consonant inside it is not. A nukta letter (which NFC
    /// keeps as two scalars), a Hinglish word and a mixed-script line are found.
    static func searchFindsWholeWordsNotFragments(_ queue: DatabaseQueue) throws {
        try queue.write { db in
            for text in [
                "मुझे हिन्दी आती है", "ये ज़रूरी है", "Kal deck bhejo, 5 baje tak", "deck भेजो", "\u{915}\u{94D}\u{200D}\u{937}त्रिय योद्धा",
                "\u{938}\u{902}\u{200C}\u{938}\u{94D}\u{915}\u{943}\u{924} पाठ",
            ] {
                try insert(try line(text), into: db)
            }
            #expect(try texts(matching: "हिन्दी", in: db) == ["मुझे हिन्दी आती है"])
            #expect(try texts(matching: "ह", in: db).isEmpty)
            #expect(try texts(matching: "\u{95B}रूरी", in: db) == ["ये ज़रूरी है"])
            #expect(try texts(matching: "bhejo", in: db) == ["Kal deck bhejo, 5 baje tak"])
            #expect(try texts(matching: "भेजो", in: db) == ["deck भेजो"])
            #expect(try texts(matching: "deck", in: db).count == 2)
            #expect(try texts(matching: "\u{915}\u{94D}\u{200D}\u{937}त्रिय", in: db).count == 1)
            #expect(try texts(matching: "षत्रिय", in: db).isEmpty)
            #expect(try texts(matching: "\u{938}\u{902}\u{200C}\u{938}\u{94D}\u{915}\u{943}\u{924}", in: db).count == 1)
            #expect(try texts(matching: "\u{938}\u{94D}\u{915}\u{943}\u{924}", in: db).isEmpty)
        }
    }

    @Test func searchFindsWholeWordsNotFragments() throws {
        try Self.searchFindsWholeWordsNotFragments(Self.database())
    }

    @Test func searchCatchesPlantedBreakDefaultTokenizer() throws {
        let defaultTokenizer = try Self.database {
            $0.replacingOccurrences(
                of: #"tokenize = "unicode61 categories 'L* N* Co Mn Mc' tokenchars '\#u{200C}\#u{200D}'""#,
                with: "tokenize = unicode61")
        }
        withKnownIssue("planted break: the default unicode61 tokenizer splits at vowel signs") {
            try Self.searchFindsWholeWordsNotFragments(defaultTokenizer)
        }
    }

    @Test func searchCatchesPlantedBreakJoiners() throws {
        let noJoiners = try Self.database {
            $0.replacingOccurrences(of: " tokenchars '\u{200C}\u{200D}'", with: "")
        }
        withKnownIssue("planted break: ZWJ and ZWNJ split a word") {
            try Self.searchFindsWholeWordsNotFragments(noJoiners)
        }
    }

    // MARK: Delete

    /// Deleting a line removes its search entry, its view rows and its legacy rows, and leaves the other line's.
    static func deletingALineRemovesWhatPointsAtIt(_ queue: DatabaseQueue) throws {
        try queue.write { db in
            let gone = try line("kal ka plan ready")
            let kept = try line("deck bhejo please")
            for each in [gone, kept] { try insert(each, into: db) }
            let view = ViewID(container: "app place", lines: [gone.id, kept.id])
            for (ordinal, each) in [gone, kept].enumerated() {
                try db.execute(
                    sql: "INSERT INTO evidence_view(view_id, ordinal, line_id) VALUES (?, ?, ?)",
                    arguments: [Data(view.bytes), ordinal, Data(each.id.bytes)])
            }
            for (space, ref, ord, each) in [
                ("wa_zpk", 122, 0, gone), ("activity", 7, 0, gone), ("activity", 7, 1, kept),
            ] {
                try db.execute(
                    sql: "INSERT INTO evidence_legacy(space, ref, ord, line_id) VALUES (?, ?, ?, ?)",
                    arguments: [space, ref, ord, Data(each.id.bytes)])
            }
            try db.execute(sql: "DELETE FROM evidence WHERE line_id = ?", arguments: [Data(gone.id.bytes)])
            #expect(try texts(matching: "plan", in: db).isEmpty)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM evidence_fts WHERE evidence_fts MATCH 'plan'") == 0)
            #expect(try texts(matching: "bhejo", in: db) == ["deck bhejo please"])
            #expect(try Data.fetchAll(db, sql: "SELECT line_id FROM evidence_view") == [Data(kept.id.bytes)])
            #expect(
                try String.fetchAll(db, sql: "SELECT space || ' ' || ref || ' ' || ord FROM evidence_legacy") == [
                    "activity 7 1"
                ])
            try db.execute(sql: "INSERT INTO evidence_fts(evidence_fts, rank) VALUES ('integrity-check', 1)")
        }
    }

    @Test func deletingALineRemovesWhatPointsAtIt() throws {
        try Self.deletingALineRemovesWhatPointsAtIt(Self.database())
    }

    @Test func deletingALineCatchesPlantedBreakSearch() throws {
        let noDeleteTrigger = try Self.database { $0.contains("CREATE TRIGGER evidence_fts_delete") ? nil : $0 }
        withKnownIssue("planted break: no search delete trigger") {
            try Self.deletingALineRemovesWhatPointsAtIt(noDeleteTrigger)
        }
    }

    @Test func deletingALineCatchesPlantedBreakViews() throws {
        let noCascade = try Self.database {
            $0.hasPrefix("CREATE TABLE evidence_view")
                ? $0.replacingOccurrences(of: " ON DELETE CASCADE", with: "") : $0
        }
        withKnownIssue("planted break: view rows do not follow their line") {
            try Self.deletingALineRemovesWhatPointsAtIt(noCascade)
        }
    }

    /// The search index keeps a deleted line's words in the file until an `optimize`; with `secure_delete` on, the
    /// optimize and a log checkpoint leave none.
    @Test func aDeletedLinesWordsLeaveTheFileOnlyAfterAnOptimize() throws {
        let store = try makeStore()
        let secret = "zxq\(UInt32.random(in: 100_000...999_999))secret"
        try store.writer.write { db in
            for number in 0..<300 { try Self.insert(try Self.line("common words here \(number)"), into: db) }
            try Self.insert(try Self.line("\(secret) appears once"), into: db)
            for number in 0..<300 { try Self.insert(try Self.line("more common words \(number)"), into: db) }
            try db.execute(sql: "DELETE FROM evidence WHERE text LIKE 'zxq%'")
        }
        func leaks() throws -> Bool {
            _ = try store.writer.writeWithoutTransaction { try $0.checkpoint(.truncate) }
            return try ["workbench.sqlite", "workbench.sqlite-wal"].contains {
                try Data(contentsOf: store.directory.appending(path: $0)).range(of: Data(secret.utf8)) != nil
            }
        }
        #expect(try leaks())
        try store.writer.write { try $0.execute(sql: "INSERT INTO evidence_fts(evidence_fts) VALUES ('optimize')") }
        #expect(try !leaks())
    }

    // MARK: Row numbers survive a rebuild

    /// After lines are deleted and the table is rebuilt by the 12-step procedure as the schema steps write it (copy
    /// the declared columns by name, drop, rename), search still points at the right lines.
    static func aRebuildKeepsSearchOnTheRightLines(_ queue: DatabaseQueue) throws {
        try queue.writeWithoutTransaction { db in
            for word in ["alpha", "bravo", "charlie", "delta", "echo"] {
                try insert(try line("word \(word)"), into: db)
            }
            try db.execute(sql: "DELETE FROM evidence WHERE text IN ('word bravo', 'word charlie')")
            let table = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'evidence'") ?? ""
            let columns = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('evidence')")
                .joined(separator: ", ")
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.inTransaction {
                try db.execute(
                    sql: table.replacingOccurrences(of: "CREATE TABLE evidence(", with: "CREATE TABLE rebuilt("))
                try db.execute(sql: "INSERT INTO rebuilt(\(columns)) SELECT \(columns) FROM evidence")
                try db.execute(sql: "DROP TABLE evidence")
                try db.execute(sql: "ALTER TABLE rebuilt RENAME TO evidence")
                return .commit
            }
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            #expect(try texts(matching: "echo", in: db) == ["word echo"])
            #expect(try texts(matching: "delta", in: db) == ["word delta"])
        }
    }

    @Test func aRebuildKeepsSearchOnTheRightLines() throws {
        try Self.aRebuildKeepsSearchOnTheRightLines(Self.database())
    }

    @Test func aRebuildCatchesPlantedBreak() throws {
        let implicitRowID = try Self.database {
            $0.replacingOccurrences(of: "id INTEGER PRIMARY KEY,\n", with: "")
                .replacingOccurrences(of: "content_rowid = 'id', ", with: "")
                .replacingOccurrences(of: "UPDATE OF id, ", with: "UPDATE OF ")
                .replacingOccurrences(of: "new.id", with: "new.rowid").replacingOccurrences(
                    of: "old.id", with: "old.rowid")
        }
        withKnownIssue("planted break: search points at the implicit rowid (research E-R1 §5)") {
            try Self.aRebuildKeepsSearchOnTheRightLines(implicitRowID)
        }
    }

    // MARK: Lines never change

    @Test func aLineNeverChangesAndItsLastSeenOnlyMovesForward() throws {
        let queue = try Self.database()
        try queue.write { db in
            let id = try Self.insert(try Self.line("deck bhejo"), into: db, seenAt: 10_000)
            try db.execute(sql: "UPDATE evidence SET last_seen = 15000 WHERE id = ?", arguments: [id])
            try db.execute(sql: "UPDATE evidence SET last_seen = 15000 WHERE id = ?", arguments: [id])
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "UPDATE evidence SET last_seen = 12000 WHERE id = ?", arguments: [id])
            }
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "UPDATE evidence SET text = 'deck mat bhejo' WHERE id = ?", arguments: [id])
            }
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "UPDATE evidence SET grant_id = 'other' WHERE id = ?", arguments: [id])
            }
            #expect(try Int64.fetchOne(db, sql: "SELECT last_seen FROM evidence") == 15000)
        }
    }

    @Test func aLegacyCitationIsNeverRewritten() throws {
        let queue = try Self.database()
        try queue.write { db in
            let line = try Self.line("deck bhejo")
            try Self.insert(line, into: db)
            try db.execute(
                sql: "INSERT INTO evidence_legacy(space, ref, ord, line_id) VALUES ('wa_zpk', 122, 0, ?)",
                arguments: [Data(line.id.bytes)])
            #expect(throws: DatabaseError.self) { try db.execute(sql: "UPDATE evidence_legacy SET ref = 123") }
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: "INSERT INTO evidence_legacy(space, ref, ord, line_id) VALUES ('Z_PK', 1, 0, ?)",
                    arguments: [Data(line.id.bytes)])
            }
            #expect(try Int.fetchOne(db, sql: "SELECT ref FROM evidence_legacy") == 122)
        }
    }

    /// A well-formed row, a tombstone and a screen line with no audience are kept; each malformed variant is refused.
    @Test func theChecksKeepWellFormedRowsAndRefuseMalformedOnes() throws {
        let queue = try Self.database()
        let insert = """
            INSERT INTO evidence(line_id, entity_key, quality, source_id, container, first_seen, last_seen, text,
                tombstone, label_id, grant_id, audience_digest, retention_class, obtained_by, walk_complete, reply_to,
                reader_version)
            VALUES (?, ?, 'stable', ?, ?, ?, ?, ?, ?, ?, 'g', ?, 'chat', ?, ?, ?, 'r1')
            """
        func row(
            id: Int = 32, entity: EntityKey = Self.whatsAppKey, source: Int = 16, container: String = "c",
            first: Int64 = 1, last: Int64 = 2,
            text: (any DatabaseValueConvertible)? = "hi", tombstone: Int = 0, label: Int = 16,
            audience: Int? = 32, obtainedBy: String = "db", walkComplete: Int? = nil, replyTo: Data? = nil,
            number: UInt8
        ) -> StatementArguments {
            [
                Data(repeating: number, count: id), Data(entity.bytes), Data(repeating: 1, count: source), container,
                first, last, text,
                tombstone, Data(repeating: 2, count: label), audience.map { Data(repeating: 3, count: $0) },
                obtainedBy, walkComplete, replyTo,
            ]
        }
        try queue.write { db in
            let kept = [
                row(number: 1), row(entity: Self.revokedKey, text: "", tombstone: 1, number: 2),
                row(
                    entity: Self.screenKey, audience: nil, obtainedBy: "ax_value", walkComplete: 1, replyTo: Data([9]),
                    number: 3),
            ]
            for arguments in kept { try db.execute(sql: insert, arguments: arguments) }
            let refused: [StatementArguments] = [
                row(id: 16, number: 10), row(first: 5, last: 4, number: 11), row(text: "", number: 12),
                row(tombstone: 1, number: 13), row(obtainedBy: "guess", number: 14), row(label: 8, number: 15),
                row(text: Data("hi".utf8), number: 16), row(text: nil, number: 17), row(source: 8, number: 18),
                row(container: "", number: 19), row(walkComplete: 2, number: 20), row(replyTo: Data(), number: 21),
                row(audience: 16, number: 22),
            ]
            for arguments in refused {
                #expect(throws: DatabaseError.self) { try db.execute(sql: insert, arguments: arguments) }
            }
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM evidence") == kept.count)
        }
    }

    static let whatsAppKey = try! EntityKey.whatsAppDirect(chat: "91@s.whatsapp.net", fromMe: false, stanzaID: "3EB0")
    static let revokedKey = try! EntityKey.whatsAppDirect(chat: "91@s.whatsapp.net", fromMe: true, stanzaID: "3EB1")
    static let screenKey = try! EntityKey.screen(container: "app place", content: ContentHash(text: "ok"), ordinal: 0)

    /// A line whose entity has an audience (WhatsApp direct and group, mail, calendar) needs its audience digest,
    /// whatever reader read it; a screen line, read by Accessibility, a page or OCR, may lack it.
    static func onlyAScreenLineMayLackItsAudience(_ queue: DatabaseQueue) throws {
        let withAudience = try [
            whatsAppKey, EntityKey.whatsAppGroup(chat: "1@g.us", author: .member("91@s.whatsapp.net"), stanzaID: "s"),
            EntityKey.gmail(messageID: "m"),
            EntityKey.calendar(externalID: "e", occurrence: UTCInstant(milliseconds: 0)),
        ]
        func insert(_ db: Database, _ key: EntityKey, audience: Bool, obtainedBy: String, number: UInt8) throws {
            try db.execute(
                sql: """
                    INSERT INTO evidence(line_id, entity_key, quality, source_id, container, first_seen, last_seen,
                        text, tombstone, label_id, grant_id, audience_digest, retention_class, obtained_by,
                        reader_version)
                    VALUES (?, ?, 'stable', zeroblob(16), 'c', 1, 1, 'hi', 0, zeroblob(16), 'g', ?, 'chat', ?, 'r1')
                    """,
                arguments: [
                    Data(repeating: number, count: 32), Data(key.bytes), audience ? Data(repeating: 3, count: 32) : nil,
                    obtainedBy,
                ])
        }
        try queue.write { db in
            var number: UInt8 = 0
            for key in withAudience {
                for obtainedBy in ["db", "api", "dom_text", "ax_value", "ocr"] {
                    number += 1
                    #expect(throws: DatabaseError.self, "\(obtainedBy)") {
                        try insert(db, key, audience: false, obtainedBy: obtainedBy, number: number)
                    }
                    number += 1
                    try insert(db, key, audience: true, obtainedBy: obtainedBy, number: number)
                }
            }
            for obtainedBy in ["ax_value", "dom_text", "ocr"] {
                number += 1
                try insert(db, screenKey, audience: false, obtainedBy: obtainedBy, number: number)
            }
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM evidence") == withAudience.count * 5 + 3)
        }
    }

    @Test func onlyAScreenLineMayLackItsAudience() throws {
        try Self.onlyAScreenLineMayLackItsAudience(Self.database())
    }

    @Test func onlyAScreenLineCatchesPlantedBreak() throws {
        let byReader = try Self.database {
            $0.replacingOccurrences(
                of: "substr(entity_key, 1, 33) = x'00000013776f726b62656e63682e656e746974792e76310000000673637265656e'",
                with: "obtained_by IN ('dom_text','ax_value','ax_title','ax_description','ocr')")
        }
        withKnownIssue(
            "planted break: the audience rule keys on the reader (draft 2), so a line from another reader may lack it"
        ) {
            try Self.onlyAScreenLineMayLackItsAudience(byReader)
        }
    }

    /// The prefix in the schema is the start of every screen key and of no other kind of key.
    @Test func theScreenPrefixInTheSchemaIsTheScreenKind() throws {
        let hex = { (bytes: ArraySlice<UInt8>) in bytes.map { String(format: "%02x", $0) }.joined() }
        let prefix = hex(Self.screenKey.bytes.prefix(33))
        #expect(Schema.evidence.joined().contains("substr(entity_key, 1, 33) = x'\(prefix)'"))
        let other = try EntityKey.screen(container: "x", content: ContentHash(text: "other"), ordinal: 9)
        #expect(hex(other.bytes.prefix(33)) == prefix)
        let others = try [
            Self.whatsAppKey, EntityKey.whatsAppGroup(chat: "1@g.us", author: .me, stanzaID: "s"),
            EntityKey.gmail(messageID: "screen"),
            EntityKey.calendar(externalID: "screen", occurrence: UTCInstant(milliseconds: 0)),
        ]
        #expect(others.allSatisfy { hex($0.bytes.prefix(33)) != prefix })
    }

    /// Each frozen column refuses a new value that its checks allow, with the freeze trigger's message.
    @Test func everyFrozenColumnRefusesANewValue() throws {
        let queue = try Self.database()
        let changes = [
            "id = 99", "line_id = zeroblob(32)", "entity_key = x'02'", "quality = 'derived'",
            "source_id = zeroblob(16)", "container = 'other'", "event_time = 7", "first_seen = first_seen - 1",
            "actor = 'someone'", "text = 'changed'", "reply_to = x'05'", "coordinate = 'p1'",
            "message_ref = 'm1'", "tombstone = 1, text = ''", "label_id = zeroblob(16)", "grant_id = 'other'",
            "audience_digest = zeroblob(32)", "retention_class = 'other'", "obtained_by = 'api'", "walk_complete = 1",
            "reader_version = 'r9'",
        ]
        try queue.write { db in
            try Self.insert(try Self.line("deck bhejo"), into: db, seenAt: 10_000)
            for change in changes {
                do {
                    try db.execute(sql: "UPDATE evidence SET \(change)")
                    Issue.record("\(change) was written")
                } catch let error as DatabaseError {
                    #expect(error.message == "an evidence line never changes", "\(change)")
                }
            }
        }
    }

    // MARK: A revoke is final

    /// After a tombstone no text line of the same entity key, or of the same container and `message_ref`, is
    /// written; a line of another message still is.
    static func aTombstoneIsFinal(_ queue: DatabaseQueue) throws {
        func insertLine(_ db: Database, _ text: String, stanza: String, member: String, ref: String?, tombstone: Bool)
            throws -> Int
        {
            let key = try EntityKey.whatsAppGroup(chat: "120363@g.us", author: .member(member), stanzaID: stanza)
            let line =
                tombstone
                ? Line.tombstone(entity: key, readerVersion: "wa 1")
                : Line(entity: key, text: text, readerVersion: "wa 1")
            try db.execute(
                sql: """
                    INSERT INTO evidence(line_id, entity_key, quality, source_id, container, first_seen, last_seen,
                        text, message_ref, tombstone, label_id, grant_id, audience_digest, retention_class,
                        obtained_by, reader_version)
                    VALUES (?, ?, 'stable', zeroblob(16), '120363@g.us', 1, 1, ?, ?, ?, zeroblob(16), 'g', zeroblob(32),
                        'chat', 'db', 'wa 1')
                    """, arguments: [Data(line.id.bytes), Data(key.bytes), line.text, ref, tombstone ? 1 : 0])
            return db.changesCount
        }
        let written = try queue.write { db in
            [
                try insertLine(db, "plan", stanza: "S1", member: "a@lid", ref: "S1", tombstone: false),
                try insertLine(db, "", stanza: "S1", member: "a@lid", ref: "S1", tombstone: true),
                try insertLine(db, "plan v2", stanza: "S1", member: "a@lid", ref: "S1", tombstone: false),
                try insertLine(db, "plan v3", stanza: "S1", member: "a@s.whatsapp.net", ref: "S1", tombstone: false),
                try insertLine(db, "other", stanza: "S2", member: "a@lid", ref: "S2", tombstone: false),
                try insertLine(db, "no ref", stanza: "S9", member: "a@lid", ref: nil, tombstone: false),
            ]
        }
        #expect(
            written == [1, 1, 0, 0, 1, 1],
            "text, tombstone; then refused: the same entity key, the same chat and message id under another author form; then another message and a line with no message id are written"
        )
        #expect(
            try queue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM evidence WHERE text LIKE 'plan%'") } == 1)
    }

    @Test func aTombstoneIsFinal() throws { try Self.aTombstoneIsFinal(Self.database()) }

    @Test func aTombstoneIsFinalCatchesPlantedBreak() throws {
        let noGuard = try Self.database { $0.contains("evidence_revoke_is_final") ? nil : $0 }
        withKnownIssue("planted break: a text line may follow its tombstone") { try Self.aTombstoneIsFinal(noGuard) }
    }

    // MARK: Written once

    /// A second insert of a line, also by REPLACE, changes nothing and keeps its citations and search entry; a new
    /// line still goes in; a REPLACE that names another line's row number is refused.
    static func aLineIsWrittenOnce(_ queue: DatabaseQueue) throws {
        try queue.write { db in
            let line = try line("kal ka plan ready")
            let id = try insert(line, into: db, seenAt: 10_000)
            let view = ViewID(container: "app place", lines: [line.id])
            try db.execute(
                sql: "INSERT INTO evidence_view(view_id, ordinal, line_id) VALUES (?, 0, ?)",
                arguments: [Data(view.bytes), Data(line.id.bytes)])
            try db.execute(
                sql: "INSERT INTO evidence_legacy(space, ref, ord, line_id) VALUES ('wa_zpk', 122, 0, ?)",
                arguments: [Data(line.id.bytes)])
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO evidence(line_id, entity_key, quality, source_id, container, first_seen,
                        last_seen, text, tombstone, label_id, grant_id, retention_class, obtained_by, reader_version)
                    VALUES (?, x'02', 'ephemeral', zeroblob(16), 'other', 1, 1, 'replaced words', 0, zeroblob(16),
                        'g2', 'chat', 'ocr', 'r9')
                    """, arguments: [Data(line.id.bytes)])
            try insert(line, into: db, seenAt: 20_000)
            let row = try Row.fetchOne(db, sql: "SELECT id, text, first_seen, last_seen, grant_id FROM evidence")
            #expect(
                row == [
                    "id": id, "text": "kal ka plan ready", "first_seen": 10_000, "last_seen": 10_000,
                    "grant_id": "consent-7",
                ])
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM evidence_view") == 1)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM evidence_legacy") == 1)
            #expect(try texts(matching: "plan", in: db) == ["kal ka plan ready"])
            #expect(try texts(matching: "replaced", in: db).isEmpty)
            try db.execute(sql: "INSERT INTO evidence_fts(evidence_fts, rank) VALUES ('integrity-check', 1)")
            try db.execute(
                sql: "UPDATE evidence SET last_seen = max(last_seen, 20000) WHERE line_id = ?",
                arguments: [Data(line.id.bytes)])
            try db.execute(sql: "UPDATE evidence SET last_seen = 20000")
            #expect(try Int64.fetchOne(db, sql: "SELECT last_seen FROM evidence") == 20_000)
            try insert(try Self.line("deck bhejo"), into: db)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM evidence") == 2)
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO evidence(id, line_id, entity_key, quality, source_id, container,
                            first_seen, last_seen, text, tombstone, label_id, grant_id, retention_class, obtained_by,
                            reader_version)
                        VALUES (?, randomblob(32), x'02', 'stable', zeroblob(16), 'c', 1, 1, 'by number', 0,
                            zeroblob(16), 'g', 'chat', 'ax_value', 'r9')
                        """, arguments: [id])
            }
            #expect(
                try String.fetchOne(db, sql: "SELECT text FROM evidence WHERE id = ?", arguments: [id])
                    == "kal ka plan ready")
        }
    }

    @Test func aLineIsWrittenOnce() throws { try Self.aLineIsWrittenOnce(Self.database()) }

    @Test func aLineIsWrittenOnceCatchesPlantedBreak() throws {
        let noGuard = try Self.database { $0.contains("CREATE TRIGGER evidence_written_once") ? nil : $0 }
        withKnownIssue("planted break: no insert guard, so REPLACE deletes and rewrites the line") {
            try Self.aLineIsWrittenOnce(noGuard)
        }
    }

    /// View and legacy rows: the same row again does nothing; the same key with another line, a REPLACE to another
    /// line, and any update are refused; a new key goes in.
    static func viewAndLegacyRowsAreWrittenOnce(_ queue: DatabaseQueue) throws {
        try queue.write { db in
            let first = try line("deck bhejo")
            let second = try line("kal milte hain")
            for each in [first, second] { try insert(each, into: db) }
            let tables = [
                ("evidence_view", "view_id, ordinal", "zeroblob(32), 0"),
                ("evidence_legacy", "space, ref, ord", "'wa_zpk', 122, 0"),
            ]
            for (table, key, values) in tables {
                let insert = "INSERT INTO \(table)(\(key), line_id) VALUES (\(values), ?)"
                try db.execute(sql: insert, arguments: [Data(first.id.bytes)])
                try db.execute(sql: insert, arguments: [Data(first.id.bytes)])
                #expect(throws: DatabaseError.self) { try db.execute(sql: insert, arguments: [Data(second.id.bytes)]) }
                #expect(throws: DatabaseError.self) {
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO \(table)(\(key), line_id) VALUES (\(values), ?)",
                        arguments: [Data(second.id.bytes)])
                }
                #expect(throws: DatabaseError.self) {
                    try db.execute(sql: "UPDATE \(table) SET line_id = ?", arguments: [Data(second.id.bytes)])
                }
                #expect(try Data.fetchAll(db, sql: "SELECT line_id FROM \(table)") == [Data(first.id.bytes)])
            }
            try db.execute(
                sql: "INSERT INTO evidence_legacy(space, ref, ord, line_id) VALUES ('wa_zpk', 122, 1, ?)",
                arguments: [Data(second.id.bytes)])
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM evidence_legacy") == 2)
        }
    }

    @Test func viewAndLegacyRowsAreWrittenOnce() throws { try Self.viewAndLegacyRowsAreWrittenOnce(Self.database()) }

    @Test func viewAndLegacyRowsCatchPlantedBreak() throws {
        let noGuards = try Self.database {
            $0.contains("CREATE TRIGGER evidence_view_written_once")
                || $0.contains("CREATE TRIGGER evidence_legacy_written_once") ? nil : $0
        }
        withKnownIssue("planted break: no insert guards on view and legacy rows") {
            try Self.viewAndLegacyRowsAreWrittenOnce(noGuards)
        }
    }

    /// Every connection of the store, reader and writer, deletes securely (ADR-015 erase rule).
    @Test func everyConnectionDeletesSecurely() throws {
        let store = try makeStore()
        #expect(try store.writer.read { try Int.fetchOne($0, sql: "PRAGMA secure_delete") } == 1)
        #expect(try store.writer.write { try Int.fetchOne($0, sql: "PRAGMA secure_delete") } == 1)
    }
}
