import Foundation
import SQLite3

enum SQLiteValue: Equatable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])
    case null
}

struct SQLiteRow {
    let values: [SQLiteValue]

    func integer(_ column: Int) -> Int64 {
        if case .integer(let value) = values[column] { value } else { 0 }
    }

    func real(_ column: Int) -> Double {
        switch values[column] {
        case .real(let value): value
        case .integer(let value): Double(value)
        default: 0
        }
    }

    func text(_ column: Int) -> String? {
        if case .text(let value) = values[column] { value } else { nil }
    }

    func blob(_ column: Int) -> [UInt8]? {
        if case .blob(let value) = values[column] { value } else { nil }
    }

    func isNull(_ column: Int) -> Bool { values[column] == .null }
}

/// A read-only connection to a database that another app writes. It never writes and never copies the file. The caller
/// opens it once and keeps it: `dataVersion` shows that another connection committed, and `readTransaction` gives every
/// read inside it one view of the file.
final class ReadOnlyDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        try Self.checkAccess(path)
        try Self.checkHeader(path)
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ReadError.unreadableStore
        }
    }

    deinit { sqlite3_close(handle) }

    /// Changes with every commit by another connection. Meant to be asked outside a transaction.
    func dataVersion() throws -> Int64 { try rows("PRAGMA data_version").first?.integer(0) ?? 0 }

    /// Runs `body` inside one read transaction: every read in it sees the same file state. Nothing stays open after.
    func readTransaction<T>(_ body: () throws -> T) throws -> T {
        _ = try rows("BEGIN")
        defer { _ = try? rows("COMMIT") }
        return try body()
    }

    // SQLite reports a refused file and a missing one as the same failure.
    static func checkAccess(_ path: String) throws {
        switch FullDiskAccess.openError(path) {
        case nil: return
        case EPERM?, EACCES?: throw ReadError.notPermitted
        case ENOENT?: throw ReadError.storeMissing
        default: throw ReadError.unreadableStore
        }
    }

    /// The first 16 bytes of every SQLite file. A file with another start is encrypted, damaged or not a database.
    static let headerMagic = Array("SQLite format 3\0".utf8)

    /// Fails closed before any read when the file does not start with the SQLite header.
    private static func checkHeader(_ path: String) throws {
        let first = FileHandle(forReadingAtPath: path).flatMap { handle in
            defer { try? handle.close() }
            return try? handle.read(upToCount: headerMagic.count)
        }
        guard let first, Array(first) == headerMagic else { throw ReadError.notADatabase }
    }

    func requireColumns(_ columns: [String], in table: String) throws {
        let present = Set(
            try rows("SELECT name FROM pragma_table_info(?)", binding: [.text(table)]).compactMap { $0.text(0) })
        guard Set(columns).isSubset(of: present) else { throw ReadError.unsupportedSchema }
    }

    func rows(_ sql: String, binding parameters: [SQLiteValue] = []) throws -> [SQLiteRow] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ReadError.unsupportedSchema
        }
        defer { sqlite3_finalize(statement) }
        for (offset, parameter) in parameters.enumerated() { bind(parameter, at: Int32(offset + 1), in: statement) }
        var result: [SQLiteRow] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            result.append(SQLiteRow(values: (0..<sqlite3_column_count(statement)).map { value(at: $0, in: statement) }))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw ReadError.unreadableStore }
        return result
    }

    private func bind(_ value: SQLiteValue, at index: Int32, in statement: OpaquePointer?) {
        let copyText = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        switch value {
        case .integer(let number): sqlite3_bind_int64(statement, index, number)
        case .real(let number): sqlite3_bind_double(statement, index, number)
        case .text(let text): sqlite3_bind_text(statement, index, text, -1, copyText)
        case .blob(let bytes): sqlite3_bind_blob(statement, index, bytes, Int32(bytes.count), copyText)
        case .null: sqlite3_bind_null(statement, index)
        }
    }

    private func value(at column: Int32, in statement: OpaquePointer?) -> SQLiteValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT: .real(sqlite3_column_double(statement, column))
        case SQLITE_NULL: .null
        case SQLITE_BLOB:
            .blob(
                sqlite3_column_blob(statement, column).map {
                    Array(
                        UnsafeBufferPointer(
                            start: $0.assumingMemoryBound(to: UInt8.self),
                            count: Int(sqlite3_column_bytes(statement, column))))
                } ?? [])
        default: .text(String(cString: sqlite3_column_text(statement, column)))
        }
    }
}
