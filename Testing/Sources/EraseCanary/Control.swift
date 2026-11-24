import Foundation
import GRDB

@testable import WorkbenchCore

/// The scan run on a store that was erased the wrong way: a plain `DELETE` of the chat with `secure_delete` off, and no
/// checkpoint. It must find the canary, and says where. A scan that finds nothing here cannot be trusted to find nothing
/// elsewhere.
enum Control {
    static func run(in folder: URL, findings: Findings) async throws {
        print("\n== control: a plain delete with secure_delete off")
        let scene = try Scene(in: folder, words: Words())
        try await scene.build()
        try await scene.store.writer.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA secure_delete = 0")
            try db.execute(sql: "DELETE FROM evidence WHERE container = ?", arguments: [Scene.chatA])
        }
        try report(scene, stage: "before a checkpoint", findings: findings)
        _ = try await scene.store.writer.writeWithoutTransaction { try $0.checkpoint(.truncate) }
        try report(scene, stage: "after a checkpoint", findings: findings)
        try scene.store.writer.close()
    }

    private static func report(_ scene: Scene, stage: String, findings: Findings) throws {
        let hits = ByteScan.hits(of: scene.words.canary, under: scene.directory).filter {
            !$0.file.hasPrefix("agent-work")
        }
        for hit in hits {
            print("     control \(stage): \(hit.file) at byte \(hit.offset) (\(hit.encoding)), \(hit.place)")
        }
        findings.expect(
            !hits.isEmpty, "control: the scan finds the canary \(stage), after a plain delete (\(hits.count) hits)")
    }
}
