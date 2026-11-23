import Foundation
import GRDB

extension Store {
    static let verifierSettingsKey = "verifier.settings"

    public func saveVerifierSettings(_ settings: Verifier.Settings) throws {
        try saveState(try Coding.json(settings), forKey: Self.verifierSettingsKey)
    }

    /// Writes one row for each proposal a reading refused. The rows go with the run's text.
    func recordDrops(_ drops: [Drop], of run: RunID) throws {
        try writer.write { db in
            for drop in drops {
                try db.execute(
                    sql: "INSERT INTO drop_reason(run_id, part, ordinal, rule, proposal) VALUES (?,?,?,?,?)",
                    arguments: [run, drop.part, drop.ordinal, drop.rule.rawValue, drop.proposal])
            }
        }
    }
}

extension Queries {
    /// The verifier's settings; the rules that need a measurement first are off until a person switches them on.
    public func verifierSettings() throws -> Verifier.Settings {
        try state(forKey: Store.verifierSettingsKey).map { try Coding.value(Verifier.Settings.self, from: $0) }
            ?? Verifier.Settings()
    }

    /// The proposals a run's reading refused, in the order of the reply: what the model said and why it was refused.
    /// Empty once a delete or the retention removed the run's text.
    public func dropReasons(of run: RunID) throws -> [Drop] {
        try reader.read { db in
            try Row.fetchAll(
                db,
                sql:
                    "SELECT part, ordinal, rule, proposal FROM drop_reason WHERE run_id = ? ORDER BY id",
                arguments: [run]
            ).map { row in
                Drop(
                    part: try row.value("part"), ordinal: try row.value("ordinal"),
                    rule: try row.enumeration("rule"), proposal: try row.value("proposal"))
            }
        }
    }
}

extension RecordedModel {
    func verifierSettings() throws -> Verifier.Settings { try store.queries.verifierSettings() }

    func record(_ drops: [Drop], of run: RunID) throws { try store.recordDrops(drops, of: run) }
}
