import Foundation
import GRDB

/// A whole copy of the store at one moment, kept in the snapshots folder.
public struct Snapshot: Sendable, Equatable {
    public let date: Date
    public let bytes: Int64
    public let url: URL
}

public enum BackupError: Error, Equatable {
    /// The store failed its check. Writes stop. `newestSnapshot` is the date of the newest backup, if one exists.
    case damaged(newestSnapshot: Date?)
    case snapshotFailed(String)
    /// A step of the schema failed. The copy made before the first step is kept at `copy`.
    case migrationFailed(copy: String, reason: String)
    case snapshotUnusable(String)
}

extension BackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .damaged(let newest):
            "Your data file failed its check, so Workbench stopped saving. "
                + (newest.map { "Your newest backup is from \($0.formatted(date: .long, time: .shortened))." }
                    ?? "There is no backup yet.")
        case .snapshotFailed(let reason):
            "Workbench could not make a backup copy of your data (\(reason)). Nothing you erased is in any backup."
        case .migrationFailed(let copy, let reason):
            "Workbench could not update your data (\(reason)). A copy from before the update is at \(copy)."
        case .snapshotUnusable(let reason): "This backup cannot be used (\(reason))."
        }
    }
}

/// The rules for which snapshots exist and when one is due. Pure: no file is read.
enum SnapshotRules {
    /// Snapshots kept after each new one. Measured on: none.
    static let kept = 3
    /// The least time between two snapshots made by the hourly hook. Measured on: none.
    static let interval: TimeInterval = 24 * 3600

    private static let dateFormat = Date.ISO8601FormatStyle(
        dateSeparator: .omitted, dateTimeSeparator: .standard, timeSeparator: .omitted, timeZoneSeparator: .omitted,
        includingFractionalSeconds: false, timeZone: .gmt)
    private static let prefix = "snapshot-"
    private static let suffix = ".sqlite"

    static func fileName(at date: Date) -> String { prefix + date.formatted(dateFormat) + suffix }

    static func date(ofFileName name: String) -> Date? {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        return try? Date(String(name.dropFirst(prefix.count).dropLast(suffix.count)), strategy: dateFormat)
    }

    static func isDue(newest: Date?, now: Date) -> Bool {
        newest.map { now.timeIntervalSince($0) >= interval } ?? true
    }

    /// The snapshots to delete: all but the newest `kept`.
    static func expired(_ snapshots: [Snapshot]) -> [Snapshot] {
        Array(snapshots.sorted { $0.date > $1.date }.dropFirst(kept))
    }
}

/// The `snapshots` folder beside the store. Every file in it is a copy of the store: a daily snapshot, the copy made
/// before a migration, the store as it was before a restore. Time Machine skips the folder.
struct BackupFolder: Sendable {
    static let folderName = "snapshots"
    static let preMigrationName = "pre-migration.sqlite"
    static let preRestoreFolderName = "pre-restore"

    let url: URL

    init(storeDirectory: URL) { url = storeDirectory.appending(path: Self.folderName) }

    var preMigrationCopy: URL { url.appending(path: Self.preMigrationName) }
    var preRestoreFolder: URL { url.appending(path: Self.preRestoreFolderName) }

    func prepare() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Store.restrict(url, to: 0o700)
        try Self.excludeFromTimeMachine(url)
    }

    static func excludeFromTimeMachine(_ folder: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = folder
        try target.setResourceValues(values)
    }

    static func isExcludedFromTimeMachine(_ folder: URL) -> Bool {
        (try? folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }

    /// Newest first. A half-written copy has a name that is no snapshot's, so it is never listed.
    func snapshots() -> [Snapshot] {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey]))
        return (files ?? []).compactMap { file in
            guard let date = SnapshotRules.date(ofFileName: file.lastPathComponent) else { return nil }
            let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return Snapshot(date: date, bytes: Int64(bytes), url: file)
        }.sorted { $0.date > $1.date }
    }

    /// `VACUUM INTO` a hidden name from a read connection, then one rename. The copy holds no deleted text.
    func writeCopy(of reader: any DatabaseReader, as destination: URL) throws {
        let partial = url.appending(path: ".partial-\(UUID().uuidString)")
        do {
            try reader.unsafeRead { db in
                try db.execute(sql: "VACUUM INTO ?", arguments: [partial.path])
            }
            try Store.restrict(partial, to: 0o600)
            guard Darwin.rename(partial.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw BackupError.snapshotFailed(error.localizedDescription)
        }
    }

    func remove(_ expired: [Snapshot]) throws {
        for snapshot in expired { try FileManager.default.removeItem(at: snapshot.url) }
    }

    /// Every file in the folder: snapshots, the pre-migration copy, the pre-restore copy and any half-written copy.
    func removeEverything() throws {
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        for file in files { try FileManager.default.removeItem(at: file) }
    }
}
