import Foundation
import GRDB

/// Backups guard against a damaged file and a bad migration. They are not in Time Machine, so they do not guard
/// against a lost disk. Every backup is newer than every erase: the end of an erase deletes them all and makes one new.
extension Store {
    /// The daily snapshots, newest first.
    public func snapshots() -> [Snapshot] { backups.snapshots() }

    /// Makes a snapshot unless the newest one is less than a day old. The hourly hook calls this.
    public func snapshotIfDue() throws {
        try backupLock.withLock {
            guard SnapshotRules.isDue(newest: backups.snapshots().first?.date, now: clock()) else { return }
            try takeSnapshot()
        }
    }

    /// Runs `quick_check`. A failure stops every write to the store and throws `damaged`. Nothing is restored by itself.
    public func checkIntegrity() throws {
        guard try Self.checkPassed(on: writer) else {
            try writer.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA query_only = ON") }
            throw BackupError.damaged(newestSnapshot: snapshots().first?.date)
        }
    }

    /// A file so damaged that SQLite refuses to read it fails the check too. Any other error is not a verdict.
    private static func checkPassed(on reader: some DatabaseReader) throws -> Bool {
        do {
            return try reader.read(quickCheckPassed)
        } catch let error as DatabaseError
            where [.SQLITE_CORRUPT, .SQLITE_NOTADB].contains(error.extendedResultCode.primaryResultCode)
        {
            return false
        }
    }

    /// Lets SQLite refresh the statistics its query plans use.
    public func optimize() throws {
        try writer.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA optimize") }
    }

    /// The last step of every erase. Rows were removed when `removedRows` is true; then every backup goes (each holds
    /// the old words) and the log is truncated. The backups go first: if the log cannot be truncated, the erase still
    /// holds. No snapshot is made here: the hourly hook makes one when none exists, so many erases cost one copy.
    func finishErase(removedRows: Bool) throws {
        try backupLock.withLock {
            guard removedRows else { return try truncateLog() }
            try backups.removeEverything()
            try truncateLog()
        }
    }

    /// Runs `body` in one write transaction and says whether it changed any row.
    func writeCountingChanges<Value>(_ body: (Database) throws -> Value) throws -> (value: Value, changed: Bool) {
        try writer.write { db in
            let before = db.totalChangesCount
            let value = try body(db)
            return (value, db.totalChangesCount != before)
        }
    }

    /// Makes a snapshot now. The caller holds `backupLock`, so no snapshot is half-way while an erase deletes them.
    private func takeSnapshot() throws {
        try backups.prepare()
        try backups.writeCopy(of: writer, as: backups.url.appending(path: SnapshotRules.fileName(at: clock())))
        try backups.remove(SnapshotRules.expired(backups.snapshots()))
    }

    static func quickCheckPassed(_ db: Database) throws -> Bool {
        try String.fetchAll(db, sql: "PRAGMA quick_check") == ["ok"]
    }

    /// Opens the schema. A store with steps to run is copied first. The copy goes when every step passed and the file
    /// passes `quick_check`; after a failure it stays, and the error says where.
    static func migrate(_ writer: DatabasePool, ownerZone: TimeZone, backups: BackupFolder) throws {
        let found = try Schema.storedVersion(writer)
        guard found > 0, found < Schema.version else { return try Schema.open(writer, ownerZone: ownerZone) }
        try backups.prepare()
        try backups.writeCopy(of: writer, as: backups.preMigrationCopy)
        func failed(_ reason: String) -> BackupError {
            .migrationFailed(copy: backups.preMigrationCopy.path, reason: reason)
        }
        do {
            try Schema.open(writer, ownerZone: ownerZone)
        } catch {
            throw failed(error.localizedDescription)
        }
        guard try checkPassed(on: writer) else { throw failed("the check after the update failed") }
        try FileManager.default.removeItem(at: backups.preMigrationCopy)
    }

    /// Puts a snapshot in place of the store in `directory`. It needs the store lock, so it cannot run while the app
    /// holds the store: call it before the store opens. The snapshot must pass `quick_check`. The files it replaces stay
    /// in the `pre-restore` folder, which holds the files of one restore only.
    public static func restore(_ snapshot: Snapshot, into directory: URL) throws {
        let lock = try StoreLock(directory: directory)
        try withExtendedLifetime(lock) {
            try requireUsable(snapshot)
            let backups = BackupFolder(storeDirectory: directory)
            try backups.prepare()
            try keepCurrentFiles(in: directory, at: backups.preRestoreFolder)
            let incoming = directory.appending(path: "workbench.sqlite.restoring")
            try? FileManager.default.removeItem(at: incoming)
            try FileManager.default.copyItem(at: snapshot.url, to: incoming)
            try restrict(incoming, to: 0o600)
            guard Darwin.rename(incoming.path, directory.appending(path: "workbench.sqlite").path) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    private static func requireUsable(_ snapshot: Snapshot) throws {
        var configuration = Configuration()
        configuration.readonly = true
        do {
            let passed = try checkPassed(on: DatabaseQueue(path: snapshot.url.path, configuration: configuration))
            guard passed else { throw BackupError.snapshotUnusable("it failed its check") }
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.snapshotUnusable(error.localizedDescription)
        }
    }

    private static func keepCurrentFiles(in directory: URL, at folder: URL) throws {
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["workbench.sqlite", "workbench.sqlite-wal", "workbench.sqlite-shm"] {
            let current = directory.appending(path: name)
            guard FileManager.default.fileExists(atPath: current.path) else { continue }
            try FileManager.default.moveItem(at: current, to: folder.appending(path: name))
        }
    }
}
