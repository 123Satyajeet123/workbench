import Foundation
import GRDB

/// Whether the extension's reader for one site can read that site's page. A reader that finds the attributes it expects
/// gone reports "stale" and writes nothing; the app keeps the report until the site reads again, and tells the person.
public enum AdapterState {
    /// What the extension sends ("type": "adapter_state").
    struct Report: Decodable {
        var site: String
        var stale: Bool
    }

    /// The name the Gmail adapter reports under.
    public static let mailSite = "Gmail"

    static let keyPrefix = "adapter_stale."
    private static let longestSiteName = 32

    /// The one sentence the person reads.
    public static func sentence(for site: String) -> String { "Workbench cannot read \(site) now: the page changed." }

    /// A name the extension may report: letters, digits and spaces, up to 32 characters.
    static func isSiteName(_ text: String) -> Bool {
        (1...longestSiteName).contains(text.count) && text.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " }
    }

    static func keep(_ report: Report, store: Store) throws -> PageHost.Reply {
        guard isSiteName(report.site) else { return PageHost.Reply(kept: false, error: "not a site name") }
        try store.record(staleness: report)
        return PageHost.Reply(kept: false)
    }
}

extension Store {
    fileprivate func record(staleness report: AdapterState.Report) throws {
        let key = AdapterState.keyPrefix + report.site
        try writer.write { db in
            if report.stale {
                try Self.upsertState(db, key: key, value: "stale", savedAt: clock())
            } else {
                try db.execute(sql: "DELETE FROM state WHERE key = ?", arguments: [key])
            }
        }
    }
}

extension Queries {
    /// The sites whose reader said its page changed, by name.
    public func staleAdapters() throws -> [String] {
        try reader.read { db in
            try String.fetchAll(
                db, sql: "SELECT key FROM state WHERE substr(key, 1, ?) = ? ORDER BY key",
                arguments: [AdapterState.keyPrefix.count, AdapterState.keyPrefix]
            ).map { String($0.dropFirst(AdapterState.keyPrefix.count)) }
        }
    }
}
