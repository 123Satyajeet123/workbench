import Foundation
import GRDB

@testable import WorkbenchCore

nonisolated(unsafe) var failures: [String] = []

func check(_ passed: Bool, _ line: String) {
    print((passed ? "ok   " : "FAIL ") + line)
    if !passed { failures.append(line) }
}

func canary(_ name: String) -> String { "zxq\(name)canary\(UInt32.random(in: 100_000...999_999))" }

let scratch = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(
    path: ".build/provenance-check-\(UUID().uuidString)")

func scratchFolder(_ name: String) -> URL { scratch.appending(path: name) }

extension Store {
    func rows(_ sql: String, _ arguments: StatementArguments = StatementArguments()) throws -> [Row] {
        try writer.read { db in try Row.fetchAll(db, sql: sql, arguments: arguments) }
    }

    func count(_ sql: String, _ arguments: StatementArguments = StatementArguments()) throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0 }
    }

    /// Every table of the schema, shadow tables of the search indexes among them.
    func tableNames() throws -> [String] { try writer.read { try Self.tables(in: $0) } }

    private static func tables(in db: Database) throws -> [String] {
        try String.fetchAll(
            db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
    }

    /// The tables that hold the word in some column, read as text.
    func tablesHolding(_ word: String) throws -> [String] {
        try writer.read { db in
            try Self.tables(in: db).filter { table in
                let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(\"\(table)\")").map { $0["name"] as String }
                let any = columns.map { "instr(CAST(\"\($0)\" AS TEXT), ?) > 0" }.joined(separator: " OR ")
                guard !any.isEmpty else { return false }
                let found =
                    try Int.fetchOne(
                        db, sql: "SELECT count(*) FROM \"\(table)\" WHERE \(any)",
                        arguments: StatementArguments(columns.map { _ in word })) ?? 0
                return found > 0
            }
        }
    }
}

/// Copies of the word in every file under the folder: the database, its log and the snapshots.
func copies(of word: String, in folder: URL) -> [String: Int] {
    var found: [String: Int] = [:]
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])!
    for case let file as URL in files
    where (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
        let data = (try? Data(contentsOf: file)) ?? Data()
        var count = 0
        var from = data.startIndex
        while let range = data.range(of: Data(word.utf8), in: from..<data.endIndex) {
            count += 1
            from = range.upperBound
        }
        if count > 0 {
            found[
                file.resolvingSymlinksInPath().path.replacingOccurrences(
                    of: folder.resolvingSymlinksInPath().path + "/", with: "")] = count
        }
    }
    return found
}
