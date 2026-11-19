import Foundation

public enum StoreError: Error, Equatable {
    case grantExpired
    case grantForOtherKind(granted: SourceKind, requested: SourceKind)
    case grantForOtherLabel(granted: String?, requested: String?)
    case fileNotRemoved(String)
}

/// The one store: `workbench.sqlite` and the recordings folder beside it. The handle serialises statements and
/// transactions, so the store is safe to share.
public final class Store: Sendable {
    public let directory: URL
    public let queries: Queries
    let database: Database
    public let clock: @Sendable () -> Date

    public init(directory: URL, clock: @escaping @Sendable () -> Date = { Date() }) throws {
        self.directory = directory
        self.clock = clock
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.restrict(directory, to: 0o700)
        let databaseFile = directory.appending(path: "workbench.sqlite")
        if !FileManager.default.fileExists(atPath: databaseFile.path) {
            FileManager.default.createFile(atPath: databaseFile.path, contents: nil)
        }
        try Self.restrict(databaseFile, to: 0o600)
        database = try Database(path: databaseFile.path)
        try Schema.open(database)
        queries = Queries(database: database, directory: directory)
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

    public func record(_ batch: ActivityBatch) throws {
        for kind in Set(batch.activities.map(\.kind.source)) { try check(batch.grant, kind: kind) }
        try database.transaction {
            for activity in batch.activities {
                try database.run(
                    "INSERT INTO activity(ts, kind, app, bundle_id, title, document, text) VALUES (?,?,?,?,?,?,?)",
                    [
                        SQLValue(activity.at), .text(activity.kind.rawValue), .text(activity.app),
                        .text(activity.bundleID), .text(activity.title), SQLValue(activity.document),
                        SQLValue(activity.text),
                    ])
            }
        }
    }

    /// A small setting: the last value saved for a key.
    public func saveState(_ value: String, forKey key: String) throws {
        try database.run(
            "INSERT INTO state(key, value, saved_at) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, saved_at = excluded.saved_at",
            [.text(key), .text(value), SQLValue(clock())])
    }

    /// The policy is the latest consent row. Every change adds one.
    public func savePolicy(_ policy: CapturePolicy) throws {
        try database.run(
            "INSERT INTO consent(ts, policy) VALUES (?,?)", [SQLValue(clock()), .text(try Coding.json(policy))])
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
