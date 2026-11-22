import Foundation
import GRDB

public enum StoreError: Error, Equatable {
    case grantExpired
    case grantForOtherKind(granted: SourceKind, requested: SourceKind)
    case grantForOtherLabel(granted: String?, requested: String?)
    case fileNotRemoved(String)
    case unreadableRow(table: String, id: Int64?, reason: String)
    case settingNotApplied(String)
    case logNotTruncated
}

public final class Store: Sendable {
    public let directory: URL
    public let queries: Queries
    let writer: DatabasePool
    public let clock: @Sendable () -> Date

    public init(
        directory: URL, clock: @escaping @Sendable () -> Date = { Date() },
        busyTimeout: TimeInterval = 10
    ) throws {
        self.directory = directory
        self.clock = clock
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.restrict(directory, to: 0o700)
        let databaseFile = directory.appending(path: "workbench.sqlite")
        try Self.createPrivateFile(databaseFile)
        try Self.restrict(databaseFile, to: 0o600)
        writer = try StoreDatabase.open(at: databaseFile, busyTimeout: busyTimeout)
        try Schema.open(writer)
        queries = Queries(reader: writer, directory: directory)
    }

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

    func check(_ grant: CaptureGrant, kind: SourceKind, label: String? = nil) throws {
        guard grant.expiresAt > clock() else { throw StoreError.grantExpired }
        guard grant.kind == kind else { throw StoreError.grantForOtherKind(granted: grant.kind, requested: kind) }
        guard label == nil || grant.label == label else {
            throw StoreError.grantForOtherLabel(granted: grant.label, requested: label)
        }
    }

    public func record(_ batch: ActivityBatch) throws {
        for kind in Set(batch.activities.map(\.kind.source)) { try check(batch.grant, kind: kind) }
        try writer.write { db in
            for activity in batch.activities {
                try db.execute(
                    sql: "INSERT INTO activity(ts, kind, app, bundle_id, title, document, text) VALUES (?,?,?,?,?,?,?)",
                    arguments: [
                        activity.at.stored, activity.kind.rawValue, activity.app, activity.bundleID, activity.title,
                        activity.document, activity.text,
                    ])
            }
        }
    }

    public func saveState(_ value: String, forKey key: String) throws {
        try writer.write { db in
            try db.execute(
                sql:
                    "INSERT INTO state(key, value, saved_at) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, saved_at = excluded.saved_at",
                arguments: [key, value, clock().stored])
        }
    }

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
