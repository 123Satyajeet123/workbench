import Foundation
import GRDB

@testable import WorkbenchCore

/// One trigger on a fresh store: build it, fire the trigger, then check rows and bytes at four moments.
struct EraseRun {
    let trigger: Trigger
    let folder: URL
    let findings: Findings

    func run() async throws {
        let scene = try Scene(in: folder, words: Words())
        try await scene.build()
        try scene.makeBackups()
        let snapshotsBefore = scene.store.snapshots().count
        findings.expect(
            snapshotsBefore == 1, "\(trigger.rawValue): before: the store has a snapshot and a pre-migration copy")
        try requireWordInEveryCopy(scene)
        let journalRows = try scene.store.count("SELECT count(*) FROM run_event WHERE run_id = ?", [scene.made.run])
        try await trigger.fire(scene)
        let bytes = ByteChecks(scene: scene, trigger: trigger, findings: findings)
        try RowChecks(scene: scene, trigger: trigger, findings: findings, journalRowsBefore: journalRows).run()
        bytes.run(stage: "store open")
        _ = try await scene.store.writer.writeWithoutTransaction { try $0.checkpoint(.truncate) }
        bytes.run(stage: "after a checkpoint")
        try scene.store.snapshotIfDue()
        bytes.run(stage: "after the next snapshot")
        try scene.store.writer.close()
        bytes.run(stage: "store closed")
    }
}

extension EraseRun {
    private static let expectedHolders: Set<String> = [
        "evidence", "item", "item_fts", "item_fts_content", "run_text", "drop_reason", "summary", "machine_block",
        "page_proposal", "proposal",
    ]

    /// Before the trigger the canary is in every kind of copy the scene made, so an erase that finds none has erased them.
    private func requireWordInEveryCopy(_ scene: Scene) throws {
        let holders = Set(try scene.store.tablesHolding(scene.words.canary))
        findings.expect(
            Self.expectedHolders.isSubset(of: holders),
            "\(trigger.rawValue): before: the canary is in \(holders.sorted()) (missing \(Self.expectedHolders.subtracting(holders).sorted()))"
        )
        let files = Set(ByteScan.hits(of: scene.words.canary, under: scene.directory).map(\.file))
        findings.expect(
            files.contains { $0.hasPrefix("workbench.sqlite") } && files.contains { $0.hasPrefix("snapshots/") },
            "\(trigger.rawValue): before: the canary is in these files: \(files.sorted())")
    }
}

/// The scan finds a word in UTF-8, in UTF-16 of both orders, and in a database file, before it is trusted to find none.
enum ScannerSelfTest {
    static func run(in folder: URL, findings: Findings) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let word = Words.random()
        for (name, bytes) in WordBytes(word).encodings {
            try (Data("xx".utf8) + bytes + Data("yy".utf8)).write(to: folder.appending(path: name))
        }
        let found = Set(ByteScan.hits(of: word, under: folder).map(\.encoding))
        findings.expect(
            found == ["utf8", "utf16le", "utf16be"], "the scan finds a word in UTF-8 and in both UTF-16 orders")
        let database = try DatabaseQueue(path: folder.appending(path: "t.sqlite").path)
        try database.write { db in
            try db.execute(sql: "CREATE TABLE t(a)")
            try db.execute(sql: "INSERT INTO t VALUES (?)", arguments: [word])
        }
        try database.close()
        let places = ByteScan.hits(of: word, under: folder).filter { $0.file == "t.sqlite" }.map(\.place)
        findings.expect(
            places.contains { $0.hasSuffix(": t") }, "the scan names the table of a database page (\(places))")
    }
}
