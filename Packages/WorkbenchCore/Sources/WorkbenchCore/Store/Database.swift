import Foundation
import GRDB

public enum SchemaError: Error, Equatable, LocalizedError {
    case newerVersion

    public var errorDescription: String? { "This store was made by a newer Workbench. Install the newer version." }
}

/// Opens `workbench.sqlite` as a WAL pool: one writer, many readers. Two processes may open the same file. The open
/// runs under a file coordinator, and a write waits up to `busyTimeout` for the other process before it fails.
enum StoreDatabase {
    static func open(at url: URL, busyTimeout: TimeInterval) throws -> DatabasePool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var opened: Result<DatabasePool, any Error>?
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { url in
            opened = Result { try openPool(at: url.path, busyTimeout: busyTimeout) }
        }
        if let coordinationError { throw coordinationError }
        return try opened!.get()
    }

    /// The size the write-ahead log is cut to after a checkpoint. Measured on: none.
    static let logSizeLimit = 64 * 1024 * 1024

    /// Set on every connection and read back. The two full-sync settings make macOS flush the drive's cache at each
    /// commit and checkpoint (plain `fsync` does not).
    private static let connectionSettings: [(name: String, value: Int)] = [
        ("secure_delete", 1), ("fullfsync", 1), ("checkpoint_fullfsync", 1), ("journal_size_limit", logSizeLimit),
    ]

    /// Set on the one writer after it opens and read back: FULL syncs the log at each commit.
    private static let writerSettings: [(name: String, value: Int)] = [("synchronous", 2)]

    private static func apply(_ settings: [(name: String, value: Int)], on db: Database) throws {
        for (name, value) in settings {
            try db.execute(sql: "PRAGMA \(name)=\(value)")
            guard try Int.fetchOne(db, sql: "PRAGMA \(name)") == value else {
                throw StoreError.settingNotApplied(name)
            }
        }
    }

    private static func openPool(at path: String, busyTimeout: TimeInterval) throws -> DatabasePool {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(busyTimeout)
        configuration.prepareDatabase { db in try apply(connectionSettings, on: db) }
        let pool = try DatabasePool(path: path, configuration: configuration)
        try pool.writeWithoutTransaction { db in try apply(writerSettings, on: db) }
        return pool
    }
}
