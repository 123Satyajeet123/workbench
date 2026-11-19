import Foundation
import GRDB

extension Date {
    /// The text a date is stored as: ISO 8601 with a Z suffix. Such text sorts in time order, so queries compare it.
    var stored: String { ISO8601Format() }
}

/// A column of a row, named or counted from zero.
protocol ColumnKey: CustomStringConvertible {
    func decode<T: DatabaseValueConvertible>(_ type: T.Type, from row: Row) throws -> T
}

extension String: ColumnKey {
    func decode<T: DatabaseValueConvertible>(_ type: T.Type, from row: Row) throws -> T {
        try row.decode(type, forColumn: self)
    }
}

extension Int: ColumnKey {
    func decode<T: DatabaseValueConvertible>(_ type: T.Type, from row: Row) throws -> T {
        try row.decode(type, atIndex: self)
    }
}

/// A value that is stored but not valid for its type: a date that is not ISO 8601, or an unknown case.
struct StoredValueError: Error, CustomStringConvertible {
    let column: String

    init(_ column: some ColumnKey) { self.column = "\(column)" }

    var description: String { "column \(column) holds a value this version cannot read" }
}

extension Row {
    /// A column that must hold a value of type `T`. A NULL or a value of another type throws.
    func value<T: DatabaseValueConvertible>(_ column: some ColumnKey) throws -> T {
        try column.decode(T.self, from: self)
    }

    /// A column that is NULL or holds a value of type `T`. A value of another type throws.
    func optionalValue<T: DatabaseValueConvertible>(_ column: some ColumnKey) throws -> T? {
        try column.decode(T?.self, from: self)
    }

    func date(_ column: some ColumnKey) throws -> Date {
        try Self.date(from: try value(column), column: column)
    }

    func optionalDate(_ column: some ColumnKey) throws -> Date? {
        try optionalValue(column).map { try Self.date(from: $0, column: column) }
    }

    func workDay(_ column: some ColumnKey) throws -> WorkDay {
        guard let day = WorkDay(try value(column)) else { throw StoredValueError(column) }
        return day
    }

    func enumeration<E: RawRepresentable>(_ column: some ColumnKey) throws -> E where E.RawValue == String {
        guard let value = E(rawValue: try value(column)) else { throw StoredValueError(column) }
        return value
    }

    /// A text column that holds JSON for `T`.
    func json<T: Decodable>(_ column: some ColumnKey, as type: T.Type = T.self) throws -> T {
        try Coding.value(type, from: try value(column))
    }

    /// Reads this row with `make`. A failure names the table and the row id, so a bad row is never skipped.
    func decoded<T>(from table: String, _ make: (Row) throws -> T) throws -> T {
        do {
            return try make(self)
        } catch {
            let id = try? optionalValue("id") as Int64?
            throw StoreError.unreadableRow(table: table, id: id ?? nil, reason: "\(error)")
        }
    }

    private static func date(from text: String, column: some ColumnKey) throws -> Date {
        guard let date = try? Date(text, strategy: .iso8601) else { throw StoredValueError(column) }
        return date
    }
}

extension Database {
    /// Every row of a query, each read by `make`. One unreadable row throws; none is skipped.
    func fetch<T>(
        _ table: String, _ sql: String, _ arguments: StatementArguments = StatementArguments(),
        as make: (Row) throws -> T
    ) throws -> [T] {
        try Row.fetchAll(self, sql: sql, arguments: arguments).map { try $0.decoded(from: table, make) }
    }
}
