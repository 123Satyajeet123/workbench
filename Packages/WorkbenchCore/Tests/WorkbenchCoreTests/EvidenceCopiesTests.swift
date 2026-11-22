import Foundation
import GRDB
import Kernel
import Lines
import Testing

@testable import WorkbenchCore

/// A revoke, and an erase of lines, take the copies of the words with them: the quote of each item that cites a line,
/// the text of the runs that read it, and the summaries built from those items.
@Suite struct EvidenceCopiesTests {
    typealias World = EvidenceIngestTests.World
    static let chat = EvidenceIngestTests.chat
    static let day = "2026-11-19"
    static let workDay = WorkDay(day)!

    /// A store with two messages, `a` (holding `secret`) and `b`, each read by one run and cited by one item and
    /// one summary. `a` is cited through the run's window, `b` through an old citation id.
    struct Planted {
        let world: World
        let secret = EvidenceIngestTests.word()
        let other = EvidenceIngestTests.word()
        let windowRun: Int64
        let oldRun: Int64
        let summaryRun: Int64

        init() throws {
            let world = try World()
            self.world = world
            let (secret, other) = (self.secret, self.other)
            _ = try world.record(
                try EvidenceFinalityTests.filler(300) + [
                    try EvidenceFinalityTests.message(
                        "\(secret) plan", stanza: "a", member: EvidenceIngestTests.member),
                    try EvidenceIngestTests.message("\(other) plan", stanza: "b", legacy: 20),
                ])
            _ = try world.store.writer.writeWithoutTransaction { try $0.checkpoint(.truncate) }
            let lineID = try world.store.writer.read {
                try Data.fetchOne(
                    $0, sql: "SELECT line_id FROM evidence WHERE text LIKE ?", arguments: ["\(secret)%"])
            }
            let windowRun = try world.store.beginRun(
                task: "t", model: "m", prompt: "p", input: "5: \(secret) plan", kinds: [.whatsapp],
                window: [WindowLine(number: 5, lineID: try #require(lineID))])
            let oldRun = try world.store.beginRun(
                task: "t", model: "m", prompt: "p", input: "20: \(other) plan", kinds: [.whatsapp])
            let summaryRun = try world.store.beginRun(
                task: "summary", model: "m", prompt: "p", input: "[1] \(secret) plan [2] \(other) plan",
                kinds: [.whatsapp])
            try world.store.writer.write { db in
                try Self.item(db, run: windowRun, cite: 5, quote: "\(secret) plan", person: "Asha")
                try Self.item(db, run: oldRun, cite: 20, quote: "\(other) plan", person: "Raj")
                try Self.summary(db, person: "Asha", run: summaryRun, words: secret)
                try Self.summary(db, person: "Raj", run: summaryRun, words: other)
            }
            self.windowRun = windowRun
            self.oldRun = oldRun
            self.summaryRun = summaryRun
        }

        static func item(_ db: Database, run: Int64, cite: Int64, quote: String, person: String) throws {
            try db.execute(
                sql: """
                    INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                        quote, created_at) VALUES ('t', ?, ?, ?, 'whatsapp', ?, ?, '2026-11-19T10:00:00Z',
                        '2026-11-19T11:00:00Z', ?, ?, '2026-11-19T12:00:00Z')
                    """,
                arguments: [
                    run, EvidenceCopiesTests.day, EvidenceCopiesTests.chat, cite, cite,
                    try Coding.json(["person": person]), quote,
                ])
        }

        static func summary(
            _ db: Database, person: String, run: Int64, words: String, day: String = EvidenceCopiesTests.day
        ) throws {
            try db.execute(
                sql: """
                    INSERT INTO summary(day, task, field, scope, fingerprint, kinds, body, saved_at)
                    VALUES (?, 't', 'person', ?, 'f', '["whatsapp"]', ?, '2026-11-19T12:00:00Z')
                    """,
                arguments: [
                    day, "person: \(person)",
                    #"{"scope":"person: \#(person)","details":[{"kind":"done","text":"\#(words)","cites":[1]}],"run":\#(run)}"#,
                ])
        }

        func revoke(_ stanza: String) throws -> IngestReport {
            try world.record([try EvidenceFinalityTests.revoke(stanza: stanza, member: EvidenceIngestTests.member)])
        }

        func row(_ sql: String) throws -> Row? { try world.store.writer.read { try Row.fetchOne($0, sql: sql) } }
        func runTexts() throws -> Int { try world.count("SELECT count(*) FROM run_text") }
    }

    @Test func aRevokeLeavesNoCopyOfItsWordsInTheFileOrItsLog() throws {
        let planted = try Planted()
        #expect(try planted.world.copies(of: planted.secret) > 3, "the word is in the line, quote, run text, summaries")
        let report = try planted.revoke("a")
        #expect(report.erasedLines == 1 && report.flaggedItems == 1)
        #expect(try planted.world.copies(of: planted.secret) == 0)
    }

    @Test func aRevokeEmptiesTheQuoteAndFlagsTheItemWhichKeepsItsMarksAndItsLinkToTheTombstone() throws {
        let planted = try Planted()
        try planted.world.store.mark(item: 1, as: .confirmed)
        _ = try planted.revoke("a")
        let item = try #require(try planted.world.store.queries.items(of: "t", on: Self.workDay).first)
        #expect(item.quote == "" && item.isSourceDeleted && item.state == .confirmed)
        #expect(item.quotedWords == "The message this came from was deleted")
        let proof = try planted.world.store.queries.proofLines(of: item, reach: 0)
        #expect(proof.map(\.line.isTombstone) == [true] && proof.map(\.isCited) == [true])
    }

    @Test func aRevokeDeletesTheTextOfTheRunsThatReadTheLineAndKeepsTheRunRows() throws {
        let planted = try Planted()
        _ = try planted.revoke("a")
        #expect(try planted.row("SELECT 1 FROM run_text WHERE run_id = \(planted.windowRun)") == nil)
        #expect(try planted.row("SELECT 1 FROM run_text WHERE run_id = \(planted.summaryRun)") == nil)
        #expect(try planted.row("SELECT 1 FROM run_text WHERE run_id = \(planted.oldRun)") != nil)
        #expect(try planted.world.count("SELECT count(*) FROM run") == 3, "the meter keeps every run")
    }

    @Test func aRevokeRemovesTheSummariesBuiltFromTheItemAndOnlyThose() throws {
        let planted = try Planted()
        try planted.world.store.writer.write {
            try Planted.summary($0, person: "Asha", run: planted.summaryRun, words: "another day", day: "2026-11-18")
        }
        _ = try planted.revoke("a")
        let scopes = try planted.world.store.writer.read {
            try Row.fetchAll($0, sql: "SELECT day, scope FROM summary ORDER BY day").map {
                "\($0["day"] as String) \($0["scope"] as String)"
            }
        }
        #expect(scopes == ["2026-11-18 person: Asha", "2026-11-19 person: Raj"])
    }

    @Test func aRevokeOfAnotherMessageLeavesTheItemItsQuoteItsRunTextAndItsSummaryIntact() throws {
        let planted = try Planted()
        _ = try planted.revoke("b")
        #expect(
            try planted.row("SELECT quote, source_deleted FROM item WHERE id = 1")?["quote"] == "\(planted.secret) plan"
        )
        #expect(try planted.row("SELECT source_deleted FROM item WHERE id = 1")?["source_deleted"] == 0)
        #expect(try planted.row("SELECT 1 FROM run_text WHERE run_id = \(planted.windowRun)") != nil)
        #expect(try planted.world.count("SELECT count(*) FROM summary WHERE scope = 'person: Asha'") == 1)
        #expect(try planted.world.copies(of: planted.secret) > 0)
        #expect(try planted.row("SELECT quote, source_deleted FROM item WHERE id = 2")?["source_deleted"] == 1)
    }

    @Test func aMessageRevokedBeforeItWasEverStoredStillErasesTheCopiesOfAnOldCitation() throws {
        let world = try World()
        let secret = EvidenceIngestTests.word()
        try world.store.writer.write { try EvidenceIngestTests.fact($0, first: 30, last: 30, quote: "\(secret) plan") }
        try world.store.writer.write { try $0.execute(sql: "UPDATE item SET scope = ?", arguments: [Self.chat]) }
        _ = try world.store.writer.writeWithoutTransaction { try $0.checkpoint(.truncate) }
        #expect(try world.copies(of: secret) > 0)
        let report = try world.record([try EvidenceIngestTests.revoke(stanza: "never-read", legacy: 30)])
        #expect(report.erasedLines == 0 && report.flaggedItems == 1)
        #expect(try world.copies(of: secret) == 0)
    }

    @Test func aRevokeOfAMessageNoItemCitesChangesNoItem() throws {
        let planted = try Planted()
        _ = try planted.world.record([
            try EvidenceFinalityTests.message("x", stanza: "z", member: EvidenceIngestTests.member)
        ])
        let report = try planted.revoke("z")
        #expect(report.flaggedItems == 0)
        #expect(try planted.world.count("SELECT count(*) FROM item WHERE source_deleted = 1") == 0)
        #expect(try planted.runTexts() == 3)
    }

    @Test func aRevokeOfAMessageCitedThroughOneChatDoesNotFlagAFactOfAnotherChat() throws {
        let planted = try Planted()
        try planted.world.store.writer.write {
            try $0.execute(sql: "UPDATE item SET scope = '120364@g.us' WHERE id = 2")
        }
        let report = try planted.revoke("b")
        #expect(report.flaggedItems == 0, "row numbers are global; the fact belongs to another chat")
        #expect(try planted.row("SELECT source_deleted FROM item WHERE id = 2")?["source_deleted"] == 0)
    }

    @Test func aRevokeEmptiesTheClosingQuoteOfAModelCloseThatCitedTheLine() throws {
        let planted = try Planted()
        try planted.world.store.writer.write { db in
            for (run, line) in [(planted.windowRun, 5), (planted.oldRun, 20)] {
                try db.execute(
                    sql: """
                        INSERT INTO item_event(item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor)
                        VALUES (1, 'close', 'done', ?, ?, '2026-11-19T10:00:00Z', '2026-11-19T10:00:00Z', ?, 'model')
                        """, arguments: [line, "closing \(planted.secret)", run])
            }
        }
        _ = try planted.revoke("a")
        let quotes = try planted.world.store.writer.read {
            try String.fetchAll($0, sql: "SELECT quote FROM item_event ORDER BY id")
        }
        #expect(quotes == ["", "closing \(planted.secret)"], "the close of the other message stays")
    }

    @Test func eraseByGrantTakesTheCopiesToo() throws {
        let planted = try Planted()
        try planted.world.store.eraseEvidence(.grant(kind: .whatsapp, label: Self.chat))
        #expect(try planted.world.copies(of: planted.secret) == 0 && planted.world.copies(of: planted.other) == 0)
        #expect(try planted.world.count("SELECT count(*) FROM item WHERE source_deleted = 1") == 2)
        #expect(try planted.world.count("SELECT count(*) FROM summary") == 0)
    }

    @Test func eraseOfAnotherChatLeavesTheCopies() throws {
        let planted = try Planted()
        try planted.world.store.eraseEvidence(.grant(kind: .whatsapp, label: "120364@g.us"))
        #expect(try planted.world.count("SELECT count(*) FROM item WHERE source_deleted = 1") == 0)
        #expect(try planted.world.count("SELECT count(*) FROM summary") == 2)
        #expect(try planted.runTexts() == 3)
    }

    @Test func deletingTheKindTakesTheLinesTheWindowRowsAndTheCopies() throws {
        let planted = try Planted()
        try planted.world.store.delete(.kind(.mail, before: nil))
        #expect(try planted.world.count("SELECT count(*) FROM run_window") == 1, "another kind leaves the window rows")
        #expect(try planted.world.copies(of: planted.secret) > 0 && planted.runTexts() == 3)
        try planted.world.store.delete(.kind(.whatsapp, before: nil))
        #expect(try planted.world.count("SELECT count(*) FROM evidence") == 0)
        #expect(try planted.world.count("SELECT count(*) FROM run_window") == 0)
        #expect(try planted.world.copies(of: planted.secret) == 0 && planted.world.copies(of: planted.other) == 0)
        #expect(try planted.runTexts() == 0 && planted.world.count("SELECT count(*) FROM run") == 3)
    }
    @Test func aSummaryOfAFlaggedItemIsBuiltAgainWithoutItsWords() async throws {
        let world = try World()
        let store = world.store
        let secret = EvidenceIngestTests.word()
        _ = try world.record([
            try EvidenceIngestTests.message("\(secret) shipped", stanza: "a", legacy: 1),
            try EvidenceIngestTests.message("needs the key", stanza: "b", legacy: 2),
        ])
        let machine = try store.createMachine(from: .team, name: "Pip")
        let model = ScriptedModel(
            #"{"summaries":[{"scope":1,"short":{"text":"Waits for the key.","cites":[2]},"details":[{"kind":"blocked","text":"Waits.","cites":[2]}]}]}"#
        )
        let summaries = Summaries(store: store, model: RecordedModel(model, store: store))
        let today = WorkDay(containing: t0)
        try await store.writer.write { db in
            for (index, text) in ["\(secret) shipped", "needs the key"].enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                        VALUES (?, 'm', 'p', 0, 's', '2026-11-19T10:00:00Z', '2026-11-19T10:00:01Z', 'done')
                        """, arguments: [machine.task])
                try db.execute(
                    sql: """
                        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at,
                            fields, quote, created_at) VALUES (?, ?, ?, ?, 'whatsapp', ?, ?, ?, ?, '{"person":"Asha"}', ?, ?)
                        """,
                    arguments: [
                        machine.task, index + 1, today.description, Self.chat, index + 1, index + 1,
                        today.start.stored, today.start.stored, text, today.start.stored,
                    ])
            }
        }
        _ = try await summaries.summaries(for: today, groupedBy: "person", of: machine.task)
        let firstInput = model.inputs.withLock { $0.last } ?? ""
        #expect(model.inputs.withLock { $0.count } == 1 && firstInput.contains(secret))
        #expect(try world.count("SELECT count(*) FROM summary") == 1)

        _ = try world.record([try EvidenceFinalityTests.revoke(stanza: "a", member: EvidenceIngestTests.member)])
        #expect(try world.count("SELECT count(*) FROM summary") == 0, "the summary that rested on the item is gone")
        #expect(try world.copies(of: secret) == 0)
        let rebuilt = try await summaries.summaries(for: today, groupedBy: "person", of: machine.task)
        let lastInput = model.inputs.withLock { $0.last } ?? ""
        #expect(model.inputs.withLock { $0.count } == 2 && !lastInput.contains(secret))
        #expect(
            !lastInput.contains("[1] Pip") && lastInput.contains("[2] Pip"),
            "the flagged item is not an input of the rebuild")
        #expect(rebuilt.first?.details.map(\.text) == ["Waits."])
    }
}
