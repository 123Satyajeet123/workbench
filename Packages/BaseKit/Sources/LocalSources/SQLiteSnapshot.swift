import Foundation
import SQLite3

enum SQLiteValue: Equatable {
    case integer(Int64)
    case real(Double)
    case text(String)
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
}

final class SQLiteSnapshot {
    private static let copyDeadline: TimeInterval = 8
    private var handle: OpaquePointer?

    init(copying path: String) throws {
        try Self.checkAccess(path)
        var source: OpaquePointer?
        guard sqlite3_open_v2(path, &source, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(source)
            throw ReadError.unreadableStore
        }
        defer { sqlite3_close(source) }
        guard
            sqlite3_open_v2("", &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
                == SQLITE_OK,
            let copy = sqlite3_backup_init(handle, "main", source, "main")
        else {
            sqlite3_close(handle)
            throw ReadError.unreadableStore
        }
        let deadline = Date().addingTimeInterval(Self.copyDeadline)
        var status: Int32
        repeat {
            status = sqlite3_backup_step(copy, 256)
            if status == SQLITE_BUSY || status == SQLITE_LOCKED { Thread.sleep(forTimeInterval: 0.02) }
        } while [SQLITE_OK, SQLITE_BUSY, SQLITE_LOCKED].contains(status) && Date() < deadline
        let finished = sqlite3_backup_finish(copy)
        guard status == SQLITE_DONE, finished == SQLITE_OK else {
            sqlite3_close(handle)
            throw ReadError.unreadableStore
        }
    }

    deinit { sqlite3_close(handle) }

    // SQLite reports a refused file and a missing one as the same failure.
    private static func checkAccess(_ path: String) throws {
        let file = open(path, O_RDONLY)
        guard file < 0 else {
            close(file)
            return
        }
        switch errno {
        case EPERM, EACCES: throw ReadError.notPermitted
        case ENOENT: throw ReadError.storeMissing
        default: throw ReadError.unreadableStore
        }
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
        case .null: sqlite3_bind_null(statement, index)
        }
    }

    private func value(at column: Int32, in statement: OpaquePointer?) -> SQLiteValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT: .real(sqlite3_column_double(statement, column))
        case SQLITE_NULL: .null
        default: .text(String(cString: sqlite3_column_text(statement, column)))
        }
    }
}
