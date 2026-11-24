import Foundation
import GRDB

@testable import WorkbenchCore

private func attempt(_ store: Store, _ sql: String) -> Bool {
    (try? store.writer.write { try $0.execute(sql: sql) }) != nil
}

/// The rows an erase may change, both ways: the triggers of a work product, a verdict and a drop reason accept the marker
/// in their word columns and refuse every other change; every redactor writes the same marker.
func runMarkerChecks() throws {
    let scene = try Scene.make(in: scratchFolder("markers"))
    let store = scene.store
    check(Redaction.marker == "[erased]", "marker: the code and the triggers use the same marker")
    let product = scene.product
    let verdict = try store.count("SELECT MIN(id) FROM judge_verdict WHERE product_id = \(product)")
    for (what, sql) in [
        ("another text", "UPDATE work_product SET text = 'other' WHERE id = \(product)"),
        ("an empty text", "UPDATE work_product SET text = '' WHERE id = \(product)"),
        (
            "the marker and another column",
            "UPDATE work_product SET text = '[erased]', subject = 'x' WHERE id = \(product)"
        ),
        ("a verdict reason alone", "UPDATE judge_verdict SET reason = '[erased]' WHERE id = \(verdict)"),
        (
            "a verdict reason and detail emptied",
            "UPDATE judge_verdict SET reason = '', detail = '' WHERE id = \(verdict)"
        ),
        (
            "the marker and a changed verdict",
            "UPDATE judge_verdict SET reason = '[erased]', detail = '[erased]', verdict = 'fail' WHERE id = \(verdict)"
        ),
    ] {
        check(!attempt(store, sql), "marker: the trigger refuses \(what)")
    }
    check(
        attempt(store, "UPDATE work_product SET text = '[erased]' WHERE id = \(product)"),
        "marker: a work product accepts the marker in its text")
    check(
        attempt(store, "UPDATE judge_verdict SET reason = '[erased]', detail = '[erased]' WHERE id = \(verdict)"),
        "marker: a verdict accepts the marker in its reason and detail")
    let run = try store.count("SELECT run_id FROM work_product WHERE id = \(product)")
    try store.writer.write { db in
        try db.execute(
            sql: "INSERT INTO run_text(run_id, input, kinds) VALUES (\(run), 'x', '[]') ON CONFLICT DO NOTHING")
        try db.execute(
            sql:
                "INSERT INTO drop_reason(run_id, part, ordinal, rule, proposal) VALUES (\(run), 'p', 0, 'r', '{\"a\":1}')"
        )
    }
    check(
        !attempt(store, "UPDATE drop_reason SET proposal = '{\"b\":2}'"), "marker: the trigger refuses another proposal"
    )
    check(
        !attempt(store, "UPDATE drop_reason SET proposal = '\"[erased]\"', rule = 'x'"),
        "marker: the trigger refuses the marker and another column")
    check(
        attempt(store, "UPDATE drop_reason SET proposal = '\"[erased]\"'"), "marker: a drop reason accepts the marker")

    try store.log(
        Decision(
            at: Date(), task: "t", kind: .trial, by: .proposer, brief: "brief words", parentBrief: "old words",
            detail: ["why": "words"]))
    let decision = try store.count("SELECT MAX(id) FROM machine_decision")
    try store.writer.write { db in
        let redactor = Redactors.all.first { $0.kind == .machineDecision }!
        try redactor.redact([DatabaseValue(value: Int64(decision))!], false, db)
    }
    let row = try store.rows("SELECT brief, parent_brief, detail FROM machine_decision WHERE id = \(decision)")[0]
    check(
        row["brief"] == "[erased]" && row["parent_brief"] == "[erased]" && row["detail"] == "\"[erased]\"",
        "marker: the redactor of a machine decision puts the marker in every word column")

    // After an erase of the chat: every table that held the word holds the marker, and no row of a derived table is gone.
    let before = try [
        "claim_cite", "product_mark", "proposal", "judge_verdict", "work_product", "action", "work_event",
    ]
    .map { ($0, try store.count("SELECT count(*) FROM \($0)")) }
    try store.eraseEvidence(scene.erasure)
    for (table, count) in before {
        check(
            try store.count("SELECT count(*) FROM \(table)") == count,
            "marker: \(table) keeps its \(count) rows after an erase")
    }
    check(
        try store.count("SELECT count(*) FROM claim_cite WHERE quote = '[erased]'") >= 1
            && (try store.count("SELECT count(*) FROM product_mark WHERE edited_text = '[erased]'")) >= 1
            && (try store.count("SELECT count(*) FROM proposal WHERE brief = '[erased]' AND name = '[erased]'")) >= 1
            && (try store.count("SELECT count(*) FROM run WHERE error = '[erased]'")) >= 1,
        "marker: a cite, an edit, a proposal and a failed run hold the marker")
}

/// An erase of web data reaches what was made from the snapshots.
func runSnapshotChecks() throws {
    let scene = try Scene.make(in: scratchFolder("snapshots"))
    let store = scene.store
    let (product, word) = try scene.addSnapshotProduct()
    let holders = Set(try store.tablesHolding(word))
    check(
        ["page_snapshot", "work_product", "claim_cite", "judge_verdict", "product_mark", "item"].allSatisfy(
            holders.contains),
        "snapshot: before, the page word is in the snapshot and in what was made from it \(holders.sorted())")
    try store.snapshotIfDue()
    check(
        copies(of: word, in: store.directory).keys.contains { $0.hasPrefix("snapshots/") },
        "snapshot: before, the page word is in a backup")
    try store.delete(.kind(.web, before: nil))
    check(
        try store.tablesHolding(word).isEmpty,
        "snapshot: after a web erase the word is in no table \(try store.tablesHolding(word))")
    check(
        copies(of: word, in: store.directory).isEmpty,
        "snapshot: after a web erase the word is in no file, log or backup \(copies(of: word, in: store.directory))")
    check(
        try store.count("SELECT count(*) FROM work_product WHERE id = \(product)") == 1
            && (try store.count("SELECT count(*) FROM work_product WHERE text = '[erased]'")) == 1,
        "snapshot: the product stays, with the marker, and no other product changed")
    check(
        !(try store.tablesHolding(scene.kept)).isEmpty, "snapshot: the kept chat's word stays after a web erase")
}
