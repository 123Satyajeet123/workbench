import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// An erase of a line takes the words the model wrote about it, not only its quote: a paraphrase of a deleted
/// message must not survive in a field of the fact.
@Suite struct EraseWordsTests {
    typealias Planted = EvidenceCopiesTests.Planted

    /// A fact of the Pip machine that cites line 5 of `windowRun`, with the model's words about it in `text` and
    /// `project`.
    private func insertFact(_ planted: Planted, task: String, extra: [String: String] = [:]) throws -> Int64 {
        let words = "Asha will do \(planted.secret) tomorrow"
        let fields = [
            "person": "Asha", "project": "Hiring \(planted.secret)", "kind": "commitment", "text": words,
            "eta": "2026-09-25", "stance": "said", "asks": "team",
        ].merging(extra) { _, new in new }
        return try planted.world.store.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                        quote, created_at) VALUES (?, ?, ?, ?, 'whatsapp', 5, 5, '2026-11-19T10:00:00Z',
                        '2026-11-19T11:00:00Z', ?, ?, '2026-11-19T12:00:00Z')
                    """,
                arguments: [
                    task, planted.windowRun, EvidenceCopiesTests.day, EvidenceCopiesTests.chat, try Coding.json(fields),
                    "\(planted.secret) tomorrow",
                ])
            return db.lastInsertedRowID
        }
    }

    @Test func anEraseEmptiesEveryTextTheModelWroteForTheFactAndKeepsItsChoicesAndMarks() throws {
        let planted = try Planted()
        let store = planted.world.store
        let pip = try store.createMachine(from: .team, name: "Pip")
        let fact = try insertFact(planted, task: pip.task)
        try store.mark(item: fact, as: .confirmed)
        #expect(try planted.world.copies(of: planted.secret) > 5)

        let report = try planted.revoke("a")
        #expect(report.flaggedItems >= 1)

        let item = try #require(try store.queries.items(of: pip.task, on: EvidenceCopiesTests.workDay).first)
        #expect(item["text"] == "" && item["project"] == "" && item["eta"] == "", "the words the model wrote")
        #expect(item["person"] == "Asha" && item["kind"] == "commitment" && item["asks"] == "team")
        #expect(item["stance"] == "said", "the choices stay")
        #expect(item.quote == "" && item.isSourceDeleted && item.state == .confirmed)
        #expect(try planted.world.copies(of: planted.secret) == 0, "no copy in a field, an event or the log")
        #expect(try store.queries.openItems(of: pip.task, lifecycle: pip.spec.lifecycle!).map(\.id) == [fact])
    }

    @Test func anEraseEmptiesTheOpenEventQuoteOfTheFactAndLeavesAnEventOnAnotherLine() throws {
        let planted = try Planted()
        let store = planted.world.store
        let pip = try store.createMachine(from: .team, name: "Pip")
        let fact = try insertFact(planted, task: pip.task)
        let other = try store.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO item_event(item_id, kind, line_id, quote, valid_at, recorded_at, run_id, actor)
                    VALUES (?, 'restate', 20, ?, '2026-11-19T10:00:00Z', '2026-11-19T10:00:00Z', ?, 'model')
                    """, arguments: [fact, "again \(planted.other)", planted.oldRun])
            return db.lastInsertedRowID
        }
        _ = try planted.revoke("a")
        let quotes = try store.writer.read {
            try String.fetchAll(
                $0, sql: "SELECT quote FROM item_event WHERE item_id = ? ORDER BY id", arguments: [fact])
        }
        #expect(quotes == ["", "again \(planted.other)"], "the open event goes; the restate cites another message")
        #expect(other > 0)
    }

    @Test func aFactThatCitesAnotherLineKeepsItsWords() throws {
        let planted = try Planted()
        let store = planted.world.store
        let pip = try store.createMachine(from: .team, name: "Pip")
        _ = try insertFact(planted, task: pip.task)
        try store.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                        quote, created_at) VALUES (?, ?, ?, ?, 'whatsapp', 20, 20, '2026-11-19T10:00:00Z',
                        '2026-11-19T11:00:00Z', ?, 'other words', '2026-11-19T12:00:00Z')
                    """,
                arguments: [
                    pip.task, planted.oldRun, EvidenceCopiesTests.day, EvidenceCopiesTests.chat,
                    try Coding.json(["person": "Raj", "kind": "plan", "text": "Raj keeps his words"]),
                ])
        }
        _ = try planted.revoke("a")
        let items = try store.queries.items(of: pip.task, on: EvidenceCopiesTests.workDay)
        let raj = try #require(items.first { $0["person"] == "Raj" })
        #expect(raj["text"] == "Raj keeps his words" && !raj.isSourceDeleted)
    }

    @Test func aFactOfAMachineThatIsNotFoundKeepsOnlyTheIdsOfTheFactsItCites() throws {
        let planted = try Planted()
        let store = planted.world.store
        _ = try insertFact(planted, task: "no-such-machine", extra: ["facts": "3,4"])
        _ = try planted.revoke("a")
        let item = try #require(try store.queries.items(of: "no-such-machine", on: EvidenceCopiesTests.workDay).first)
        #expect(item["facts"] == "3,4" && item["text"] == "" && item["kind"] == "" && item["person"] == "")
        #expect(try planted.world.copies(of: planted.secret) == 0)
    }

    @Test func theFieldsWithoutWordsAreTheChoicesMembersDatesAndComputedValues() {
        #expect(HelperSpec.team.fieldsWithoutWords == ["person", "kind", "stance", "asks", Item.factsField])
        #expect(HelperSpec.derailment.fieldsWithoutWords == ["kind", "severity", Item.factsField])
    }
}
