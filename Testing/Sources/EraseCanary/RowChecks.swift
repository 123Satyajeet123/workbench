import Foundation
import GRDB

@testable import WorkbenchCore

/// What the design promises at row level, after the trigger: the facts that rest on the erased line keep their place and
/// their marks and lose their words; the words they made are emptied; the tombstone of a revoke stays; the journal stays.
struct RowChecks {
    let scene: Scene
    let trigger: Trigger
    let findings: Findings
    let journalRowsBefore: Int

    private var store: Store { scene.store }
    private var made: Made { scene.made }
    private var erasedMarker: String { Redaction.marker }

    func run() throws {
        try noWordInAnyTable()
        try searchIndexesFindNothing()
        try facts()
        try derivedWords()
        try journal()
        if trigger == .revoke { try tombstone() }
        try recordings()
    }

    private func noWordInAnyTable() throws {
        for name in trigger.gone {
            guard let word = scene.words.all.first(where: { $0.name == name })?.word else { continue }
            let tables = try store.tablesHolding(word)
            findings.expect(tables.isEmpty, "\(trigger.rawValue): \(name) is in no table (found in \(tables))")
        }
    }

    private func searchIndexesFindNothing() throws {
        for word in trigger.gone.compactMap({ name in scene.words.all.first { $0.name == name }?.word }) {
            let lines = try store.count("SELECT count(*) FROM evidence_fts WHERE evidence_fts MATCH ?", [word])
            let facts = try store.count("SELECT count(*) FROM item_fts WHERE item_fts MATCH ?", [word])
            findings.expect(
                lines == 0 && facts == 0, "\(trigger.rawValue): both search indexes find no \(word.prefix(6))...")
        }
    }

    private func facts() throws {
        let ids = made.items.map(String.init).joined(separator: ",")
        guard made.items.count == 2 else { return findings.fail("the reading made \(made.items.count) facts, not 2") }
        let rows = try store.rows("SELECT id, source_deleted, quote, fields FROM item WHERE id IN (\(ids)) ORDER BY id")
        guard trigger.keepsFacts else {
            findings.expect(rows.isEmpty, "\(trigger.rawValue): the facts went with their kind (\(rows.count) left)")
            return
        }
        let erasedFacts = trigger == .revoke ? [rows.first].compactMap { $0 } : Array(rows)
        for row in erasedFacts {
            let id: Int64 = row["id"]
            findings.expect(
                (row["source_deleted"] as Int) == 1 && (row["quote"] as String).isEmpty,
                "\(trigger.rawValue): fact \(id) is flagged and has no quote")
            findings.expect(
                !(row["fields"] as String).contains(scene.words.canary)
                    && !(row["fields"] as String).contains(scene.words.sameChat),
                "\(trigger.rawValue): fact \(id) has no word in its fields")
            let home = try store.count("SELECT count(*) FROM fact_home WHERE item_id = ?", [id])
            findings.expect(home == 1, "\(trigger.rawValue): fact \(id) keeps its place")
        }
        try keptFactIsWhole(rows)
        try mark(of: made.items[0])
        try home(of: made.items[0])
    }

    private func keptFactIsWhole(_ rows: [Row]) throws {
        guard trigger == .revoke, rows.count == 2 else { return }
        let text: String = rows[1]["fields"]
        findings.expect(
            (rows[1]["source_deleted"] as Int) == 0 && text.contains(scene.words.sameChat),
            "\(trigger.rawValue): the fact of the other message keeps its words")
    }

    private func mark(of item: Int64) throws {
        let marks = try store.count("SELECT count(*) FROM mark WHERE item_id = ? AND state = 'confirmed'", [item])
        findings.expect(marks == 1, "\(trigger.rawValue): the fact keeps its mark")
    }

    private func home(of item: Int64) throws {
        let home = try store.count(
            "SELECT count(*) FROM fact_home WHERE item_id = ? AND object_id = ?", [item, made.home])
        findings.expect(home == 1, "\(trigger.rawValue): the fact keeps the home the person chose")
    }

    private func derivedWords() throws {
        let texts = try store.rows("SELECT input, reply FROM run_text WHERE run_id = ?", [made.run])
        findings.expect(
            texts.allSatisfy { ($0["input"] as String) == erasedMarker && ($0["reply"] as String?) == erasedMarker },
            "\(trigger.rawValue): the run text is emptied or gone (\(texts.count) row)")
        let drops = try store.rows("SELECT proposal FROM drop_reason WHERE run_id = ?", [made.run])
        findings.expect(
            drops.allSatisfy { ($0["proposal"] as String) == "\"\(erasedMarker)\"" },
            "\(trigger.rawValue): the refused proposal is emptied or gone (\(drops.count) row)")
        findings.expect(
            try store.count("SELECT count(*) FROM summary") == 0, "\(trigger.rawValue): the summary is gone")
        let blocks = try store.rows("SELECT spec FROM machine_block")
        findings.expect(
            blocks.allSatisfy { !($0["spec"] as String).contains(scene.words.canary) },
            "\(trigger.rawValue): the page block has no word of the line")
        let why = try store.rows("SELECT why FROM proposal").map { $0["why"] as String }
        findings.expect(
            why.allSatisfy { $0 == erasedMarker }, "\(trigger.rawValue): the proposal holds no word of the line")
    }

    private func journal() throws {
        let rows = try store.count("SELECT count(*) FROM run_event WHERE run_id = ?", [made.run])
        findings.expect(
            rows == journalRowsBefore && rows > 0,
            "\(trigger.rawValue): the journal of the reading is kept (\(rows) rows)")
    }

    private func tombstone() throws {
        let tombstones = try store.rows(
            "SELECT length(text) AS size FROM evidence WHERE tombstone = 1 AND message_ref = 'A1'")
        findings.expect(
            tombstones.count == 1 && (tombstones[0]["size"] as Int) == 0,
            "\(trigger.rawValue): the tombstone stays, with no words")
    }

    private func recordings() throws {
        guard let folder = made.recordingFolder else { return }
        let exists = FileManager.default.fileExists(atPath: folder.path)
        findings.expect(
            exists != trigger.removesRecordings,
            "\(trigger.rawValue): the recording folder is \(trigger.removesRecordings ? "gone" : "kept")")
    }
}
