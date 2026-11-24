import Foundation
import GRDB

@testable import WorkbenchCore

/// A reader that holds a snapshot of the log while a revoke erases a line. The log cannot be truncated while a reader
/// needs its frames, so the words stay in the `-wal` file. The erase must say so, and the words must go when the reader
/// lets go.
enum HeldLog {
    static func run(in folder: URL, findings: Findings) async throws {
        print("\n== a reader holds the log while the sender revokes the message")
        let scene = try Scene(in: folder, words: Words(), busyTimeout: 0.2)
        try await scene.build()
        let reader = HoldingReader(store: scene.store)
        reader.start()
        let failure = await erase(scene)
        let held = ByteScan.hits(of: scene.words.canary, under: scene.directory)
        for hit in held { print("     while held: \(hit.file) at byte \(hit.offset) (\(hit.encoding)), \(hit.place)") }
        findings.expect(
            failure != nil, "the erase reports that the log could not be truncated (\(String(describing: failure)))")
        reader.release()
        try scene.store.truncateLog()
        for hit in ByteScan.hits(of: scene.words.canary, under: scene.directory) {
            findings.leak(
                "held log, after the reader let go: canary in \(hit.file) at byte \(hit.offset) (\(hit.encoding)), \(hit.place)"
            )
        }
        try scene.store.writer.close()
    }

    private static func erase(_ scene: Scene) async -> (any Error)? {
        do {
            try await Trigger.revoke.fire(scene)
            return nil
        } catch {
            return error
        }
    }
}

/// A read transaction that stays open until it is released.
private final class HoldingReader: @unchecked Sendable {
    private let store: Store
    private let started = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    init(store: Store) { self.store = store }

    func start() {
        Thread.detachNewThread { [self] in
            try? store.writer.read { db in
                _ = try Int.fetchOne(db, sql: "SELECT count(*) FROM evidence")
                started.signal()
                released.wait()
            }
        }
        started.wait()
    }

    func release() { released.signal() }
}
