import Foundation
import GRDB

extension Store {
    static let runSettingsKey = "run.settings"

    /// Keeps the numbers a person or an eval may change. A number that would leave a formula undefined is refused.
    public func saveRunSettings(_ settings: RunSettings) throws {
        try saveState(try Coding.json(try settings.validated()), forKey: Self.runSettingsKey)
    }
}

extension Queries {
    /// The saved numbers over the defaults; the defaults for a store that has none.
    public func runSettings() throws -> RunSettings {
        try reader.read { db in try Self.runSettings(in: db) }
    }

    static func runSettings(in db: Database) throws -> RunSettings {
        guard
            let json = try String.fetchOne(
                db, sql: "SELECT value FROM state WHERE key = ?", arguments: [Store.runSettingsKey])
        else { return .standard }
        return try Coding.value(RunSettings.self, from: json)
    }
}
