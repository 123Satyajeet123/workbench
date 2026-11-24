import Foundation

@testable import WorkbenchCore

/// The erase, both ways: the erased word is in no table, no search shadow table, no log and no backup afterwards, at a
/// derivation depth of eight; the kept word stays everywhere it was; the preview says what the erase does.
func runEraseChecks(closureOnly: Bool) throws {
    let label = closureOnly ? "closure only" : "dual"
    print("-- erase, \(label)")
    let scene = try Scene.make(in: scratchFolder("erase-\(label)"))
    let store = scene.store
    if closureOnly {
        try finishBackfill(store)
        check(
            try store.provenanceBackfillIsComplete(),
            "\(label): the backfill flag is set, so the old joins are not used")
    }
    let flaggedBefore = try store.count("SELECT count(*) FROM item WHERE source_deleted = 1")

    let derivedKinds = Set(
        try store.rows("SELECT DISTINCT node_kind FROM derivation").map { $0["node_kind"] as String })
    let wanted: Set<String> = [
        "item", "item_event", "summary", "machine_block", "page_proposal", "proposal", "work_product", "claim_cite",
        "judge_verdict", "product_mark", "run", "action", "work_event",
    ]
    check(
        wanted.isSubset(of: derivedKinds),
        "writers: every writer of a derived row wrote its edges (missing \(wanted.subtracting(derivedKinds).sorted()))")
    check(
        try store.count("SELECT count(*) FROM run_window") == 0
            && (try store.count("SELECT count(*) FROM run_input WHERE kind = 'line'")) > 0,
        "run_input: new runs write run_input and no run_window row")

    let holders = Set(try store.tablesHolding(scene.erased))
    let expected: Set<String> = [
        "evidence", "item", "item_event", "run_text", "summary", "machine_block", "page_proposal", "work_product",
        "claim_cite", "judge_verdict", "product_mark", "proposal", "item_fts", "run", "action", "work_event",
    ]
    check(expected.isSubset(of: holders), "before: the erased word is in \(expected.subtracting(holders).sorted()) too")

    try store.snapshotIfDue()
    check(
        copies(of: scene.erased, in: store.directory).keys.contains { $0.hasPrefix("snapshots/") },
        "before: the erased word is in a backup")

    let preview = try store.previewEvidenceErasure(scene.erasure)
    let erased = try store.eraseEvidence(scene.erasure)
    check(preview == erased, "preview: the preview counts equal the erase counts \(preview.citingFacts) facts")
    let flaggedAfter = try store.count("SELECT count(*) FROM item WHERE source_deleted = 1")
    check(
        flaggedAfter - flaggedBefore == preview.citingFacts,
        "preview: the facts the erase flagged (\(flaggedAfter - flaggedBefore)) equal the preview (\(preview.citingFacts))"
    )

    check(
        try store.tablesHolding(scene.erased).isEmpty,
        "after: the erased word is in no table \(try store.tablesHolding(scene.erased))")
    check(
        copies(of: scene.erased, in: store.directory).isEmpty,
        "after: the erased word is in no file, log or backup \(copies(of: scene.erased, in: store.directory))")
    let ids = (scene.erasedFacts + scene.chain).map(String.init).joined(separator: ",")
    check(
        try store.count("SELECT count(*) FROM item WHERE id IN (\(ids)) AND source_deleted = 1")
            == scene.erasedFacts.count + scene.chain.count,
        "depth: the facts and the chain of \(Scene.chainLength) facts made from them are all flagged")

    let keptHolders = Set(try store.tablesHolding(scene.kept))
    let keptExpected: Set<String> = [
        "evidence", "item", "run_text", "summary", "work_product", "claim_cite", "judge_verdict", "product_mark",
    ]
    check(
        keptExpected.isSubset(of: keptHolders),
        "kept: the kept word stays in \(keptExpected.sorted()) (lost: \(keptExpected.subtracting(keptHolders).sorted()))"
    )
    check(
        try store.count(
            "SELECT count(*) FROM item WHERE id IN (\(scene.keptFacts.map(String.init).joined(separator: ","))) AND source_deleted = 0"
        ) == scene.keptFacts.count,
        "kept: the facts of the kept chat are not flagged")
    check(!copies(of: scene.kept, in: store.directory).isEmpty, "kept: the kept word is still in the file")

    let again = try store.eraseEvidence(scene.erasure)
    check(again.lines == 0 && again.citingFacts == 0, "erase: a second erase of the same chat reaches nothing")
}
