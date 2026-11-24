import Foundation
import GRDB

@testable import WorkbenchCore

/// The edges and inputs of a store, one line each, without the time they were written.
func dump(_ store: Store) throws -> [String] {
    let edges = try store.rows(
        """
        SELECT node_kind || '|' || quote(node_id) || '|' || from_kind || '|' || quote(from_id) || '|' || edge || '|'
            || ifnull(run_id, '') || '|' || rule AS line FROM derivation ORDER BY line
        """)
    let inputs = try store.rows(
        "SELECT run_id || '|' || ordinal || '|' || kind || '|' || quote(ref) AS line FROM run_input ORDER BY line")
    return edges.map { "edge " + ($0["line"] as String) } + inputs.map { "input " + ($0["line"] as String) }
}

func runBackfillChecks() throws {
    let source = try Scene.make(in: scratchFolder("backfill-source"), linesPerChat: 6)
    try makeOldShaped(source.store)
    try source.store.writer.writeWithoutTransaction { try $0.checkpoint(.truncate) }
    let (unbrokenFolder, killedFolder) = (scratchFolder("backfill-unbroken"), scratchFolder("backfill-killed"))
    try FileManager.default.copyItem(at: source.store.directory, to: unbrokenFolder)
    try FileManager.default.copyItem(at: source.store.directory, to: killedFolder)

    let unbroken = try Store(directory: unbrokenFolder)
    check(
        try !unbroken.provenanceBackfillIsComplete() && (try unbroken.count("SELECT count(*) FROM derivation")) == 0,
        "backfill: opening a store does no backfill, so launch is not blocked")
    try unbroken.advanceProvenanceBackfill(budget: 120, batchSize: 5)
    let whole = try dump(unbroken)
    check(
        try unbroken.provenanceBackfillIsComplete() && whole.count > 20,
        "backfill: an unbroken run ends with the flag and \(whole.count) rows")

    var killed = try Store(directory: killedFolder)
    for _ in 0..<7 { try killed.backfillBatch(size: 5) }
    let partial = try dump(killed)
    check(
        !partial.isEmpty && partial.count < whole.count,
        "backfill: after 7 batches \(partial.count) of \(whole.count) rows are written")

    try killed.writer.write { db in
        try db.execute(
            sql: "CREATE TEMP TRIGGER boom BEFORE INSERT ON derivation BEGIN SELECT RAISE(ABORT, 'killed'); END")
    }
    let cursor =
        try killed.rows("SELECT value FROM state WHERE key = ?", [Store.backfillCursorKey]).first?["value"] as String?
    var failed = false
    do { try killed.backfillBatch(size: 5) } catch { failed = true }
    let rolledBack = try dump(killed) == partial
    let cursorKept =
        try killed.rows("SELECT value FROM state WHERE key = ?", [Store.backfillCursorKey]).first?["value"] as String?
        == cursor
    check(
        failed && rolledBack && cursorKept,
        "backfill: a batch that dies in the middle leaves the rows and the cursor as they were")
    try killed.writer.write { try $0.execute(sql: "DROP TRIGGER boom") }

    killed = try Store(directory: killedFolder)
    check(try !killed.provenanceBackfillIsComplete(), "backfill: the restarted store is not complete yet")
    try killed.advanceProvenanceBackfill(budget: 120, batchSize: 5)
    let resumed = try dump(killed) == whole
    check(
        try killed.provenanceBackfillIsComplete() && resumed,
        "backfill: a kill and a restart end with the same rows as an unbroken run")

    try killed.writer.write { try $0.execute(sql: "DELETE FROM state WHERE key LIKE 'provenance.backfill.%'") }
    try killed.advanceProvenanceBackfill(budget: 120, batchSize: 5)
    check(try dump(killed) == whole, "backfill: a second full run adds nothing")
}
