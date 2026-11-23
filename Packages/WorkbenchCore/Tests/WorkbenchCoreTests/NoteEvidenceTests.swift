import Foundation
import GRDB
import Kernel
import Lines
import Synchronization
import Testing

@testable import WorkbenchCore

/// Project notes as evidence: each paragraph is a line of its own source, kept in the person's words, written through
/// the one writer and erased through the one erase path.
@Suite struct NoteEvidenceTests {
    static let owner = try! PersonID("owner-1")
    static let boltPay = NoteID(object: "Bolt Pay")!
    static let atlas = NoteID(object: "Atlas")!

    final class World: Sendable {
        let store: Store
        final class Clock: Sendable {
            let now = Mutex(t0)
        }

        private let clock = Clock()

        init() throws {
            let clock = clock
            store = try Store(directory: temporaryDirectory(), clock: { clock.now.withLock { $0 } })
        }

        func advance() { clock.now.withLock { $0 = $0.addingTimeInterval(60) } }

        /// Saves what the document has pending, then moves the clock on so a later version is the later one.
        @discardableResult
        func save(_ document: inout NoteDocument) async throws -> IngestReport {
            guard let change = document.pendingChange() else { return IngestReport() }
            let report = try await store.saveNote(change, owner: NoteEvidenceTests.owner)
            document.didSave(change)
            advance()
            return report
        }

        func note(_ texts: [String]) async throws -> NoteDocument { try await note(NoteEvidenceTests.boltPay, texts) }

        func note(_ id: NoteID, _ texts: [String]) async throws -> NoteDocument {
            var document = NoteDocument(note: id)
            document.replace(0..<0, with: texts.joined(separator: "\n"))
            try await save(&document)
            return document
        }

        func count(_ sql: String, _ arguments: StatementArguments = []) throws -> Int {
            try store.writer.read { try Int.fetchOne($0, sql: sql, arguments: arguments) ?? 0 }
        }

        struct StoredRow: Sendable {
            var grant: String
            var container: String
            var actor: String
            var retention: String
            var quality: String
            var text: String
            var source: Data
            var label: Data
            var audience: Data
            var entity: Data
        }

        func evidence() throws -> [StoredRow] {
            try store.writer.read {
                try Row.fetchAll($0, sql: "SELECT * FROM evidence WHERE tombstone = 0 ORDER BY id").map {
                    StoredRow(
                        grant: $0["grant_id"], container: $0["container"], actor: $0["actor"],
                        retention: $0["retention_class"], quality: $0["quality"], text: $0["text"],
                        source: $0["source_id"], label: $0["label_id"], audience: $0["audience_digest"],
                        entity: $0["entity_key"])
                }
            }
        }

        func run(_ sql: String) throws { try store.writer.write { try $0.execute(sql: sql) } }

        func checkpoint() throws { _ = try store.writer.writeWithoutTransaction { try $0.checkpoint(.truncate) } }

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

        func lineID(containing word: String) throws -> Data {
            try #require(
                try store.writer.read {
                    try Data.fetchOne(
                        $0, sql: "SELECT line_id FROM evidence WHERE text LIKE ?", arguments: ["%\(word)%"])
                })
        }

        /// A fact that quotes a line, made by a run that read it: the copies a revoke must empty.
        func cite(_ word: String, quote: String) throws {
            let run = try store.beginRun(
                task: "t", model: "m", prompt: "p", input: "1: \(quote)", kinds: [.note],
                window: [WindowLine(number: 1, lineID: try lineID(containing: word))])
            try store.writer.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                            quote, created_at) VALUES ('t', ?, '2026-09-21', 'Bolt Pay', 'note', 1, 1,
                            '2026-09-21T10:00:00Z', '2026-09-21T11:00:00Z', '{"person":"Asha"}', ?, '2026-09-21T12:00:00Z')
                        """, arguments: [run, quote])
            }
        }

        /// The quote of the one fact, and whether it was flagged as having lost its source.
        func fact() throws -> (quote: String, sourceDeleted: Bool) {
            try store.writer.read {
                let row = try #require(try Row.fetchOne($0, sql: "SELECT quote, source_deleted FROM item"))
                return (row["quote"], row["source_deleted"] == 1)
            }
        }
    }

    static func word() -> String { "zxq\(UInt32.random(in: 100_000...999_999))note" }

    // MARK: The note is its own source

    @Test func aNoteLineHasItsOwnSourceItsGrantItsAudienceAndTheOwnersActor() async throws {
        let world = try World()
        let document = try await world.note(["Send the deck"])
        let row = try #require(try world.evidence().first)
        let source = try SourceDescriptor.note.sourceID(owner: Self.owner)
        #expect(row.grant == "note:Bolt Pay" && row.container == "Bolt Pay" && row.actor == "me")
        #expect(row.retention == "note" && row.quality == "stable" && row.text == "Send the deck")
        #expect(row.source == Data(source.bytes) && row.label == Data(Label(source: source).id.bytes))
        #expect(row.audience == Data(AudienceDigest(owner: "me", members: []).bytes))
        #expect(row.entity == Data(try EntityKey.block(document.blocks[0].id, of: Self.boltPay).bytes))
    }

    @Test func twoOwnersNeverShareTheSourceOfTheirNotes() throws {
        let other = try PersonID("owner-2")
        #expect(try SourceDescriptor.note.sourceID(owner: Self.owner) != SourceDescriptor.note.sourceID(owner: other))
        #expect(
            try SourceDescriptor.note.sourceID(owner: Self.owner)
                != SourceDescriptor.whatsAppChat.sourceID(owner: Self.owner))
        #expect(SourceRegistry.descriptor(named: "workbench.note") == .note)
        #expect(SourceRegistry.descriptor(named: "whatsapp.chat") == .whatsAppChat)
    }

    @Test func aNoteLineReadsAsTheOwnersOwnWords() async throws {
        let world = try World()
        _ = try await world.note(["Send the deck"])
        let lines = try world.store.queries.currentLines(
            in: ["Bolt Pay"], from: day(-1), to: day(2))
        let line = try #require(lines.first)
        #expect(line.actor == "me" && line.provenance?.authority == .ownWords && line.text == "Send the deck")
    }

    // MARK: Consent

    @Test func aNoteIsWrittenWhileCapturePausedOrOffBecauseItIsNotCaptured() async throws {
        let world = try World()
        try world.store.savePolicy(CapturePolicy(mode: .off))
        #expect(try await world.note(["Still saved"]).hasUnsavedChanges == false)
        try world.store.savePolicy(CapturePolicy(mode: .paused(until: t0.addingTimeInterval(3600))))
        var document = try await world.note(["Saved too"])
        document.replace(0..<0, with: "x")
        try await world.save(&document)
        #expect(try world.count("SELECT count(*) FROM evidence") == 3)
    }

    @Test func aProjectOnTheDenyListIsNotWritten() async throws {
        let world = try World()
        try world.store.savePolicy(CapturePolicy(denyList: [.note: ["Bolt Pay"]]))
        await #expect(throws: EvidenceError.consentWithdrawn) { _ = try await world.note(["Refused"]) }
        #expect(try world.count("SELECT count(*) FROM evidence") == 0)
        #expect(try await world.note(NoteEvidenceTests.atlas, ["Fine"]).text == "Fine")
    }

    // MARK: An edit is a new version of the same entity

    @Test func anEditedBlockIsANewLineOfTheSameEntityAndTheOldLineStaysAsAnEarlierVersion() async throws {
        let world = try World()
        var document = try await world.note(["Send the deck"])
        document.replace(13..<13, with: " today")
        try await world.save(&document)
        let rows = try world.evidence()
        #expect(rows.map(\.text) == ["Send the deck", "Send the deck today"])
        #expect(Set(rows.map(\.entity)).count == 1)
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).map(\.text) == ["Send the deck today"])
    }

    @Test func theEntityKeyIsTheNoteAndTheBlock() async throws {
        let one = try EntityKey.block(BlockID("b1")!, of: Self.boltPay)
        #expect(one == (try EntityKey.block(BlockID("b1")!, of: Self.boltPay)))
        #expect(one != (try EntityKey.block(BlockID("b2")!, of: Self.boltPay)))
        #expect(one != (try EntityKey.block(BlockID("b1")!, of: Self.atlas)))
    }

    @Test func theOrderOfTheBlocksSurvivesEditsMovesAndAReopen() async throws {
        let world = try World()
        var document = try await world.note(["One", "Two", "Three"])
        document.move(document.blocks[2].id, by: -2)
        document.replace(0..<0, with: "A ")
        try await world.save(&document)
        let expected = ["A Three", "One", "Two"]
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).map(\.text) == expected)
        let reopened = try Store(directory: world.store.directory)
        #expect(try reopened.queries.noteBlocks(of: Self.boltPay).map(\.text) == expected)
    }

    @Test func aNoteWithNoWordsHasNoLinesAndReadsEmpty() async throws {
        let world = try World()
        var document = NoteDocument(note: Self.boltPay)
        try await world.save(&document)
        #expect(try world.count("SELECT count(*) FROM evidence") == 0)
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).isEmpty)
    }

    // MARK: A deleted block erases its words and every copy

    @Test func aDeletedBlockLeavesNoCopyOfItsWordsInTheFileOrItsLogAndEmptiesTheFactThatQuotedIt() async throws {
        let world = try World()
        let secret = Self.word()
        let kept = Self.word()
        var document = try await world.note(["\(secret) plan", "\(kept) plan"])
        document.replace(0..<1, with: "\(secret) plan edited")
        try await world.save(&document)
        try world.cite(secret, quote: "\(secret) plan edited")
        try world.checkpoint()
        #expect(try world.copies(of: secret) > 3, "the word is in two versions, the quote and the run text")
        let start = document.blocks[0].text.utf16.count + 1
        document.replace(0..<start, with: "")
        let report = try await world.save(&document)
        #expect(report.erasedLines == 2 && report.flaggedItems == 1 && report.tombstones == 1)
        #expect(try world.copies(of: secret) == 0)
        #expect(try world.copies(of: kept) > 0, "the other block stays")
        let fact = try world.fact()
        #expect(fact.quote == "" && fact.sourceDeleted)
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).map(\.text) == ["\(kept) plan"])
    }

    @Test func aBlockOfAnotherNoteIsNotErasedByTheDeleteOfThisOne() async throws {
        let world = try World()
        let words = Self.word()
        var bolt = try await world.note(Self.boltPay, [words])
        let atlas = try await world.note(Self.atlas, [words])
        bolt.replace(0..<words.utf16.count, with: "")
        try await world.save(&bolt)
        #expect(try world.store.queries.noteBlocks(of: Self.atlas).map(\.text) == [words])
        #expect(atlas.text == words)
        #expect(try world.copies(of: words) > 0)
    }

    @Test func aDeletedNameIsFinalSoTheSameNameCannotWriteWordsAgain() async throws {
        let world = try World()
        var document = try await world.note(["Gone"])
        let dead = document.blocks[0].id
        document.replace(0..<4, with: "")
        try await world.save(&document)
        let report = try await world.store.saveNote(
            NoteChange(note: Self.boltPay, blocks: [NoteBlock(id: dead, text: "Back")], endings: [], order: [dead]),
            owner: Self.owner)
        #expect(report.refusedAfterRevoke == 1 && report.inserted == 0)
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).isEmpty)
        #expect(try world.count("SELECT count(*) FROM evidence WHERE tombstone = 0") == 0)
    }

    // MARK: A merge erases nothing

    @Test func aMergedBlockKeepsItsWordsItsLineAndTheFactThatQuotesItAndShowsWhereItWent() async throws {
        let world = try World()
        let moved = Self.word()
        var document = try await world.note(["Intro", "\(moved) later"])
        try world.cite(moved, quote: "\(moved) later")
        let survivor = document.blocks[0].id
        document.replace(5..<6, with: "")
        try await world.save(&document)
        try world.checkpoint()
        let fact = try world.fact()
        #expect(fact.quote == "\(moved) later" && !fact.sourceDeleted)
        #expect(try world.copies(of: moved) > 0)
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).map(\.text) == ["Intro\(moved) later"])
        let move = try #require(
            try world.store.queries.paragraphMove(ofLine: world.lineID(containing: "\(moved) later")))
        #expect(
            move == ParagraphMove(note: Self.boltPay, into: survivor)
                && ParagraphMove.words == "Moved into another paragraph")
    }

    @Test func aMachineDoesNotReadAMergedBlockAsASecondCopyOfTheWordsThatMovedIntoAnother() async throws {
        let world = try World()
        var document = try await world.note(["Intro", "later"])
        document.replace(5..<6, with: "")
        try await world.save(&document)
        let lines = try world.store.queries.currentLines(in: ["Bolt Pay"], from: day(-1), to: day(2))
        #expect(lines.map(\.text) == ["Introlater"])
    }

    @Test func aLineThatNothingMergedHasNoMove() async throws {
        let world = try World()
        let words = Self.word()
        _ = try await world.note([words])
        #expect(try world.store.queries.paragraphMove(ofLine: world.lineID(containing: words)) == nil)
    }

    @Test func deletingTheBlockThatTookInAMergeErasesTheWordsThatMovedIntoItToo() async throws {
        let world = try World()
        let moved = Self.word()
        var document = try await world.note(["Intro", "\(moved) later"])
        document.replace(5..<6, with: "")
        try await world.save(&document)
        try world.checkpoint()
        #expect(try world.copies(of: moved) > 0)
        document.replace(0..<document.text.utf16.count, with: "")
        try await world.save(&document)
        #expect(try world.copies(of: moved) == 0)
        #expect(try world.count("SELECT count(*) FROM container_order") == 0)
    }

    // MARK: A deleted note

    @Test func aDeletedNoteLeavesNoWordsOfAnyBlockOrVersionAndNothingOfAnotherNote() async throws {
        let world = try World()
        let words = (0..<3).map { _ in Self.word() }
        let other = Self.word()
        var bolt = try await world.note(["\(words[0]) a", "\(words[1]) b", "\(words[2]) c"])
        bolt.replace(0..<0, with: "edit ")
        try await world.save(&bolt)
        bolt.replace(len(bolt, 0)..<len(bolt, 0) + 1, with: "")
        try await world.save(&bolt)
        _ = try await world.note(Self.atlas, ["\(other) kept"])
        try world.cite(words[1], quote: "\(words[1]) b")
        try world.checkpoint()
        for word in words { #expect(try world.copies(of: word) > 0) }
        let report = try await world.store.deleteNote(Self.boltPay, owner: Self.owner)
        #expect(report.flaggedItems == 1)
        for word in words { #expect(try world.copies(of: word) == 0) }
        #expect(try world.copies(of: other) > 0)
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).isEmpty)
        #expect(try world.store.queries.noteBlocks(of: Self.atlas).map(\.text) == ["\(other) kept"])
        #expect(try world.count("SELECT count(*) FROM container_order WHERE container = 'Bolt Pay'") == 0)
    }

    private func len(_ document: NoteDocument, _ index: Int) -> Int {
        document.blocks.prefix(index).reduce(0) { $0 + $1.text.utf16.count + 1 }
    }

    @Test func theDeleteInSettingsErasesEveryNoteAndAgeNeverDoes() async throws {
        let world = try World()
        let words = Self.word()
        _ = try await world.note([words])
        _ = try await world.note(Self.atlas, [words])
        try world.checkpoint()
        try world.store.delete(.everything(before: t0.addingTimeInterval(86_400 * 365)))
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).map(\.text) == [words], "age erases no note")
        try world.store.delete(.kind(.note, before: t0.addingTimeInterval(86_400 * 365)))
        #expect(try world.copies(of: words) > 0)
        try world.store.delete(.kind(.note, before: nil))
        #expect(try world.copies(of: words) == 0)
        #expect(
            try world.count("SELECT count(*) FROM container_order") == 0
                && world.count("SELECT count(*) FROM evidence") == 0
        )
    }

    @Test func deletingEverythingErasesNotesToo() async throws {
        let world = try World()
        let words = Self.word()
        _ = try await world.note([words])
        try world.store.delete(.everything(before: nil))
        #expect(try world.copies(of: words) == 0 && world.count("SELECT count(*) FROM container_order") == 0)
    }

    @Test func eraseOfOneNotesGrantRemovesItsLinesThroughTheOneErasePath() async throws {
        let world = try World()
        let words = Self.word()
        _ = try await world.note([words])
        _ = try await world.note(Self.atlas, ["kept"])
        let counts = try world.store.eraseEvidence(.grant(kind: .note, label: "Bolt Pay"))
        #expect(counts.lines == 1)
        try world.checkpoint()
        #expect(try world.copies(of: words) == 0)
        #expect(try world.store.queries.noteBlocks(of: Self.atlas).map(\.text) == ["kept"])
    }

    // MARK: One transaction

    @Test func aFailureWhileWritingTheStructureLeavesNoLineBehind() async throws {
        let world = try World()
        try world.run("CREATE TRIGGER no_rows BEFORE INSERT ON container_order BEGIN SELECT RAISE(ABORT, 'no'); END")
        var document = NoteDocument(note: Self.boltPay)
        document.replace(0..<0, with: "Half saved")
        await #expect(throws: (any Error).self) { try await world.save(&document) }
        #expect(try world.count("SELECT count(*) FROM evidence") == 0)
    }

    @Test func aSecondSaveOfTheSameChangeWritesNothingNewSoAReplayAfterACrashIsSafe() async throws {
        let world = try World()
        var document = NoteDocument(note: Self.boltPay)
        document.replace(0..<0, with: "One\nTwo")
        let change = try #require(document.pendingChange())
        _ = try await world.store.saveNote(change, owner: Self.owner)
        let again = try await world.store.saveNote(change, owner: Self.owner)
        #expect(again.inserted == 0 && again.seenAgain == 2)
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).map(\.text) == ["One", "Two"])
    }

    @Test func aThousandBlocksSaveAndReadBackInOrder() async throws {
        let world = try World()
        let texts = (0..<1000).map { "Paragraph \($0)" }
        var document = try await world.note(texts)
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).map(\.text) == texts)
        document.replace(0..<0, with: "x")
        let clock = ContinuousClock()
        let change = try #require(document.pendingChange())
        let spent = try await clock.measure { try await world.store.saveNote(change, owner: Self.owner) }
        #expect(spent < .seconds(1), "one edit of 1000 blocks saved in \(spent)")
    }

    @Test func devanagariAndEmojiSurviveASaveAndAReadBack() async throws {
        let world = try World()
        let text = "नमस्ते 👍 दुनिया"
        _ = try await world.note([text, "🇮🇳 ok"])
        #expect(try world.store.queries.noteBlocks(of: Self.boltPay).map(\.text) == [text, "🇮🇳 ok"])
    }

    @Test func aStepOfTheSchemaNeverChanges() {
        let index = Schema.steps.firstIndex(of: Schema.notes)
        #expect(index == Schema.steps.count - 1)
        #expect(Schema.stepDigests[index!] == "691728ffc8182e5038f061b669f468892f54cfec8a128305015d68061eef70eb")
    }
}
