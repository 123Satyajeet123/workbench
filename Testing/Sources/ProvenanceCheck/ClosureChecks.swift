import Foundation
import GRDB

@testable import WorkbenchCore

/// Puts a store back in the shape of one made before this step: no edge, the runs' lines in `run_window`, no backfill
/// cursor or flag.
func makeOldShaped(_ store: Store) throws {
    try store.writer.write { db in
        try db.execute(sql: "DELETE FROM derivation")
        try db.execute(
            sql:
                "INSERT INTO run_window(run_id, ordinal, line_id) SELECT run_id, ordinal, ref FROM run_input WHERE kind = 'line'"
        )
        try db.execute(sql: "DELETE FROM run_input")
        try db.execute(sql: "DELETE FROM state WHERE key LIKE 'provenance.backfill.%'")
    }
}

func finishBackfill(_ store: Store) throws {
    try store.advanceProvenanceBackfill(budget: 120, batchSize: 500)
}

private struct Reach {
    var items: Set<Int64>
    var events: Set<Int64>
    var blocks: Set<String>
    var summaries: Set<String>
    var pageProposals: Set<Int64>
    var runs: Set<Int64>
}

private func reach(of old: OldJoinReach) -> Reach {
    Reach(
        items: Set(old.items), events: Set(old.events), blocks: Set(old.blocks), summaries: Set(old.summaries),
        pageProposals: Set(old.pageProposals), runs: Set(old.runs))
}

private func reach(of closure: EraseClosure) -> Reach {
    func numbers(_ kind: NodeKind) -> Set<Int64> { Set(closure.ids(ofKind: kind).compactMap(Int64.fromDatabaseValue)) }
    func texts(_ kind: NodeKind) -> Set<String> { Set(closure.ids(ofKind: kind).compactMap(String.fromDatabaseValue)) }
    return Reach(
        items: numbers(.item), events: numbers(.itemEvent), blocks: texts(.machineBlock), summaries: texts(.summary),
        pageProposals: numbers(.pageProposal), runs: numbers(.run))
}

/// The old joins' set against the closure's, per kind: every row the old joins reach must be in the closure. Prints each
/// difference in both directions.
func compareOldJoinsToClosure(_ store: Store, _ selection: LineSelection, _ label: String) throws {
    let (old, closure) = try store.writer.read { db in
        (try Store.oldJoinReach(of: selection, in: db), try Store.closure(of: selection, in: db))
    }
    let (before, after) = (reach(of: old), reach(of: closure))
    func compare<Element: Hashable & Comparable>(_ kind: String, _ old: Set<Element>, _ new: Set<Element>) {
        let missing = old.subtracting(new).sorted()
        let added = new.subtracting(old).sorted()
        check(
            missing.isEmpty,
            "\(label): \(kind): old joins \(old.count), closure \(new.count), old not in closure \(missing)")
        if !added.isEmpty { print("     \(label): \(kind): the closure also reaches \(added)") }
    }
    compare("items", before.items, after.items)
    compare("events", before.events, after.events)
    compare("blocks", before.blocks, after.blocks)
    compare("summaries", before.summaries, after.summaries)
    compare("page proposals", before.pageProposals, after.pageProposals)
    compare("runs", before.runs, after.runs)
}

func runOldAgainstNewChecks() throws {
    let scene = try Scene.make(in: scratchFolder("old-shapes"))
    try makeOldShaped(scene.store)
    check(
        try scene.store.count("SELECT count(*) FROM run_window") > 0
            && (try scene.store.count("SELECT count(*) FROM derivation")) == 0,
        "old shape: the store has window rows and no edge")
    try finishBackfill(scene.store)
    check(try scene.store.provenanceBackfillIsComplete(), "backfill: the flag is set")
    check(
        try scene.store.count("SELECT count(*) FROM run_window") == 0,
        "backfill: every run_window row moved to run_input")
    let erasedLines = LineSelection(
        sql: "SELECT line_id FROM evidence WHERE grant_id = ?",
        arguments: [Store.grantID(kind: SourceDescriptor.typedNote.consent, label: Scene.erasedScope)])
    try compareOldJoinsToClosure(scene.store, erasedLines, "window shapes")

    let legacy = try LegacyScene.make(in: scratchFolder("legacy-shapes"))
    try makeOldShaped(legacy.store)
    try finishBackfill(legacy.store)
    for chat in 0..<2 { try compareOldJoinsToClosure(legacy.store, legacy.erasure(chat: chat), "legacy chat \(chat)") }
    let closure = try legacy.store.writer.read { try Store.closure(of: legacy.erasure(chat: 0), in: $0) }
    check(
        closure.items == [legacy.firstFact, legacy.windowedFact, legacy.typedFact],
        "legacy: the first chat reaches its facts and the typed fact, not the fact of the other chat \(closure.items)")
    let other = try legacy.store.writer.read { try Store.closure(of: legacy.erasure(chat: 1), in: $0) }
    check(other.items == [legacy.secondFact], "legacy: the second chat reaches only its own fact \(other.items)")
}

/// A revoke of one message goes through the tombstone: the edges and inputs of its line move to the tombstone, and the
/// erase of copies starts there.
func runRevokeChecks(closureOnly: Bool) throws {
    let label = closureOnly ? "closure only" : "dual"
    let legacy = try LegacyScene.make(in: scratchFolder("revoke-\(label)"))
    let store = legacy.store
    if closureOnly { try finishBackfill(store) }
    check(
        !(try store.tablesHolding(legacy.erased)).isEmpty, "revoke \(label): before, the word of the message is stored")
    try legacy.revoke(stanza: "s0", chat: 0)
    check(
        try store.tablesHolding(legacy.erased).isEmpty,
        "revoke \(label): after, the word is in no table \(try store.tablesHolding(legacy.erased))")
    check(copies(of: legacy.erased, in: store.directory).isEmpty, "revoke \(label): after, the word is in no file")
    let flagged = Set(
        try store.rows("SELECT id FROM item WHERE source_deleted = 1").map { $0["id"] as Int64 })
    check(
        flagged == [legacy.firstFact, legacy.windowedFact, legacy.typedFact],
        "revoke \(label): the facts that cite the message are flagged, the fact of the other chat is not \(flagged)")
    check(!(try store.tablesHolding(legacy.kept)).isEmpty, "revoke \(label): the word of the other chat stays")
}
