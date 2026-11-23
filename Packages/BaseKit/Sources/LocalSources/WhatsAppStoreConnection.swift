import Foundation

/// What a change check of WhatsApp's store reports. Two stamps are equal when nothing changed between the checks.
public enum StoreStamp: Sendable, Equatable {
    /// The store is open: the file it is, and the count of commits other connections made (`PRAGMA data_version`).
    case commits(FileIdentity, Int64)
    /// The store could not be opened: the size and change time of the store and of its write-ahead log.
    case files(store: FileStamp?, log: FileStamp?)
}

/// Which file a path names: a new file under the same path has another identity.
public struct FileIdentity: Sendable, Equatable {
    var device: Int32
    var inode: UInt64

    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        device = info.st_dev
        inode = info.st_ino
    }
}

/// The size and change time of one file. A write-ahead log shrinks at a checkpoint, so the pair counts, not a growth.
public struct FileStamp: Sendable, Equatable {
    var seconds: Int
    var nanoseconds: Int
    var size: Int64

    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        seconds = info.st_mtimespec.tv_sec
        nanoseconds = info.st_mtimespec.tv_nsec
        size = info.st_size
    }
}

/// The one read-only connection to WhatsApp's `ChatStorage.sqlite`, kept open while the app runs. It opens the file
/// read-only, never copies it, and holds no transaction between reads: a change by WhatsApp shows in `stamp()` through
/// `PRAGMA data_version`, and every read inside one `read` sees one state of the file. On open, and after every change
/// of `data_version`, it checks again that the file is a WAL-mode SQLite store with the columns the readers use. A file
/// replaced under the same path is a new store: the connection reopens and checks it from the start.
public final class WhatsAppStoreConnection: @unchecked Sendable {
    private struct Open {
        var database: ReadOnlyDatabase
        var identity: FileIdentity
        var checkedVersion: Int64
    }

    private static let registry = Registry()

    /// The connection of this container, one for the whole process.
    public static func shared(for container: URL) -> WhatsAppStoreConnection { registry.connection(for: container) }

    let storePath: String
    private let logPath: String
    private let lock = NSLock()
    private var open: Open?

    init(container: URL) {
        storePath = container.appending(path: "ChatStorage.sqlite").path
        logPath = storePath + "-wal"
    }

    /// Runs `body` in one read transaction of the store, after the checks. `body` must not keep the database.
    func read<T>(_ body: (ReadOnlyDatabase) throws -> T) throws -> T {
        try lock.withLock {
            let database = try ready()
            return try database.readTransaction { try body(database) }
        }
    }

    /// What changed since the last stamp is a store change. Opens the store when it is not open; when it cannot, the
    /// stamp is the state of the files, so a later change still shows and a new open is tried.
    public func stamp() -> StoreStamp {
        lock.withLock {
            guard let database = try? ready(), let open else { return filesStamp }
            return (try? database.dataVersion()).map { .commits(open.identity, $0) } ?? filesStamp
        }
    }

    private var filesStamp: StoreStamp { .files(store: FileStamp(path: storePath), log: FileStamp(path: logPath)) }

    private func ready() throws -> ReadOnlyDatabase {
        guard let identity = FileIdentity(path: storePath) else {
            open = nil
            try ReadOnlyDatabase.checkAccess(storePath)
            throw ReadError.unreadableStore
        }
        if var current = open, current.identity == identity {
            let version = try current.database.dataVersion()
            if version != current.checkedVersion {
                try Self.check(current.database)
                current.checkedVersion = version
                open = current
            }
            return current.database
        }
        open = nil
        let database = try ReadOnlyDatabase(path: storePath)
        try Self.check(database)
        open = Open(database: database, identity: identity, checkedVersion: try database.dataVersion())
        return database
    }

    /// Fails closed unless the store is in WAL mode and has every table and column the readers use.
    private static func check(_ database: ReadOnlyDatabase) throws {
        guard try database.rows("PRAGMA journal_mode").first?.text(0) == "wal" else {
            throw ReadError.unsupportedSchema
        }
        try database.requireColumns(
            ["Z_PK", "ZCONTACTJID", "ZSESSIONTYPE", "ZPARTNERNAME", "ZLASTMESSAGEDATE"], in: "ZWACHATSESSION")
        try database.requireColumns(
            [
                "Z_PK", "ZCHATSESSION", "ZMESSAGEDATE", "ZMESSAGETYPE", "ZTEXT", "ZISFROMME", "ZGROUPMEMBER",
                "ZSTANZAID", "ZFLAGS",
            ], in: "ZWAMESSAGE")
        try database.requireColumns(["ZMESSAGE", "ZMEDIALOCALPATH", "ZTITLE", "ZMETADATA"], in: "ZWAMEDIAITEM")
        try database.requireColumns(
            ["Z_PK", "ZCHATSESSION", "ZMEMBERJID", "ZCONTACTNAME", "ZFIRSTNAME", "ZISACTIVE"], in: "ZWAGROUPMEMBER")
        try database.requireColumns(["ZJID", "ZPUSHNAME"], in: "ZWAPROFILEPUSHNAME")
        try database.requireColumns(["Z_UUID"], in: "Z_METADATA")
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var connections: [String: WhatsAppStoreConnection] = [:]

        func connection(for container: URL) -> WhatsAppStoreConnection {
            lock.withLock {
                let path = container.standardizedFileURL.path
                if let known = connections[path] { return known }
                let made = WhatsAppStoreConnection(container: container)
                connections[path] = made
                return made
            }
        }
    }
}
