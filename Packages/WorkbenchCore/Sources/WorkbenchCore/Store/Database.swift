import Foundation
import SQLite3

enum SQLValue: Sendable, Equatable {
    case null
    case int(Int64)
    case real(Double)
    case text(String)

    init(_ value: String?) { self = value.map { .text($0) } ?? .null }
    init(_ value: Double?) { self = value.map { .real($0) } ?? .null }
    init(_ value: Date) { self = .text(value.ISO8601Format()) }
    init(_ value: Int64?) { self = value.map { .int($0) } ?? .null }
    init(_ value: Int) { self = .int(Int64(value)) }

    var string: String? { if case .text(let value) = self { value } else { nil } }
    var integer: Int64? { if case .int(let value) = self { value } else { nil } }
    var double: Double? { if case .real(let value) = self { value } else { nil } }
    var date: Date? { string.flatMap { try? Date($0, strategy: .iso8601) } }
}

struct DatabaseError: Error, LocalizedError {
    let description: String

    var errorDescription: String? { description }
}

public enum SchemaError: Error, Equatable, LocalizedError {
    case newerVersion

    public var errorDescription: String? { "This store was made by a newer Workbench. Install the newer version." }
}

/// A thin SQLite handle. Two processes may open the same file: WAL and a busy timeout.
final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()

    init(path: String) throws {
        guard
            sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
                == SQLITE_OK
        else { throw DatabaseError(description: "cannot open \(path)") }
        sqlite3_busy_timeout(handle, 10_000)
        try run("PRAGMA journal_mode=WAL")
        try run("PRAGMA foreign_keys=ON")
        try run("PRAGMA secure_delete=ON")
    }

    deinit { sqlite3_close(handle) }

    @discardableResult
    func run(_ sql: String, _ parameters: [SQLValue] = []) throws -> Int64 {
        try lock.withLock {
            _ = try step(sql, parameters)
            return sqlite3_last_insert_rowid(handle)
        }
    }

    /// Runs `body` as one transaction: all its statements commit together or none do.
    /// The handle stays locked meanwhile, so no other thread's statement runs in between.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        try run("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try run("COMMIT")
            return result
        } catch {
            _ = try? run("ROLLBACK")
            throw error
        }
    }

    func rows(_ sql: String, _ parameters: [SQLValue] = []) throws -> [[SQLValue]] {
        try lock.withLock { try step(sql, parameters) }
    }

    private func step(_ sql: String, _ parameters: [SQLValue]) throws -> [[SQLValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure(sql) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in parameters.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .null: sqlite3_bind_null(statement, position)
            case .int(let number): sqlite3_bind_int64(statement, position, number)
            case .real(let number): sqlite3_bind_double(statement, position, number)
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, transient)
            }
        }
        var result: [[SQLValue]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                result.append(
                    (0..<sqlite3_column_count(statement)).map { column in
                        switch sqlite3_column_type(statement, column) {
                        case SQLITE_INTEGER: .int(sqlite3_column_int64(statement, column))
                        case SQLITE_FLOAT: .real(sqlite3_column_double(statement, column))
                        case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(statement, column)))
                        default: .null
                        }
                    })
            case SQLITE_DONE:
                return result
            default:
                throw failure(sql)
            }
        }
    }

    private func failure(_ sql: String) -> DatabaseError {
        DatabaseError(description: "\(String(cString: sqlite3_errmsg(handle))) in: \(sql)")
    }
}
