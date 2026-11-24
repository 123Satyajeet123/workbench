import Foundation
import GRDB

public enum StoreError: Error, Equatable {
    case grantExpired
    case grantForOtherKind(granted: SourceKind, requested: SourceKind)
    case grantForOtherLabel(granted: String?, requested: String?)
    case fileNotRemoved(String)
    /// A row that cannot be read as its type: the table, the row's id and the reason.
    case unreadableRow(table: String, id: Int64?, reason: String)
    case settingNotApplied(String)
    /// The write-ahead log still holds rows after a checkpoint: another connection is reading it.
    case logNotTruncated
    /// A person confirmed a close on an item that has no pending proposal to close.
    case noCloseProposal(item: Int64)
}

/// The one store: `workbench.sqlite` and the recordings folder beside it. Only the app process opens it. The native
/// browser host opens none and sends each write to the app. Threads share one store.
public final class Store: Sendable {
    public let directory: URL
    public let queries: Queries
    let writer: DatabasePool
    public let clock: @Sendable () -> Date
    /// Replaces `AuditPolicy.pick` for the new item at an index of a reading, so a test can choose its picks.
    let isAudited: (@Sendable (Int) -> Bool)?
    let ingestGate = SerialGate()
    let backups: BackupFolder
    /// Held while a snapshot is made and while an erase deletes the backups, so a snapshot cannot outlive an erase.
    let backupLock = NSLock()

    public init(
        directory: URL, clock: @escaping @Sendable () -> Date = { Date() }, ownerZone: TimeZone = .current,
        busyTimeout: TimeInterval = 10, isAudited: (@Sendable (Int) -> Bool)? = nil
    ) throws {
        self.directory = directory
        self.clock = clock
        self.isAudited = isAudited
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.restrict(directory, to: 0o700)
        try BackupFolder.excludeFromTimeMachine(directory)
        backups = BackupFolder(storeDirectory: directory)
        try backups.prepare()
        let databaseFile = directory.appending(path: "workbench.sqlite")
        try Self.createPrivateFile(databaseFile)
        try Self.restrict(databaseFile, to: 0o600)
        writer = try StoreDatabase.open(at: databaseFile, busyTimeout: busyTimeout)
        try Self.migrate(writer, ownerZone: ownerZone, backups: backups)
        queries = Queries(reader: writer, directory: directory)
    }

    /// Creates the file at mode 0600 unless it exists. A file another process already made is never truncated.
    private static func createPrivateFile(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        if descriptor >= 0 {
            Darwin.close(descriptor)
        } else if errno != EEXIST {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func restrict(_ url: URL, to mode: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    /// Every write of personal data passes here first: the grant must be live and name this kind and label.
    func check(_ grant: CaptureGrant, kind: SourceKind, label: String? = nil) throws {
        guard grant.expiresAt > clock() else { throw StoreError.grantExpired }
        guard grant.kind == kind else { throw StoreError.grantForOtherKind(granted: grant.kind, requested: kind) }
        guard label == nil || grant.label == label else {
            throw StoreError.grantForOtherLabel(granted: grant.label, requested: label)
        }
    }

    /// Writes the batch's rows and returns their ids, in the batch's order.
    @discardableResult
    public func record(_ batch: ActivityBatch) throws -> [Int64] {
        for kind in Set(batch.activities.map(\.kind.source)) { try check(batch.grant, kind: kind) }
        return try writer.write { db in
            try batch.activities.map { activity in
                try db.execute(
                    sql: "INSERT INTO activity(ts, kind, app, bundle_id, title, document, text) VALUES (?,?,?,?,?,?,?)",
                    arguments: [
                        activity.at.stored, activity.kind.rawValue, activity.app, activity.bundleID, activity.title,
                        activity.document, activity.text,
                    ])
                return db.lastInsertedRowID
            }
        }
    }

    public func saveState(_ value: String, forKey key: String) throws {
        try writer.write { db in try Self.upsertState(db, key: key, value: value, savedAt: clock()) }
    }

    /// The policy is the latest consent row. Every change adds one.
    public func savePolicy(_ policy: CapturePolicy) throws {
        let json = try Coding.json(policy)
        try writer.write { db in
            try db.execute(sql: "INSERT INTO consent(ts, policy) VALUES (?,?)", arguments: [clock().stored, json])
        }
    }
}

extension Store: CapturePolicyProvider {
    public func currentPolicy() throws -> CapturePolicy { try queries.policy() }
}

/// JSON in and out of text columns: one encoder, one decoder, stable key order.
enum Coding {
    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func value<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(text.utf8))
    }
}
