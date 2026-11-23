import Foundation
import SQLite3
import WorkbenchCore

/// The founder's yes to the model terms, as his own store keeps it. The builder opens that store read-only and runs one
/// SELECT of one state row; it reads nothing else there and writes nothing.
enum FounderModelTerms {
    private static let query = "SELECT value FROM state WHERE key = '\(ModelTerms.stateKey)'"

    static func read(from folder: URL) throws -> String {
        var database: OpaquePointer?
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
            sqlite3_close(database)
        }
        let path = folder.appending(path: "workbench.sqlite").path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
            sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK
        else { throw BuildFailure.modelTermsUnreadable(database.map { String(cString: sqlite3_errmsg($0)) } ?? path) }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let text = sqlite3_column_text(statement, 0), case let value = String(cString: text), !value.isEmpty
            else { throw BuildFailure.modelTermsNotConfirmed }
            return value
        case SQLITE_DONE: throw BuildFailure.modelTermsNotConfirmed
        default: throw BuildFailure.modelTermsUnreadable(String(cString: sqlite3_errmsg(database)))
        }
    }
}
