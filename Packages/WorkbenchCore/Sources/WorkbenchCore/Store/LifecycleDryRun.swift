import Foundation
import GRDB

/// What the fact lifecycle step changes in a store, counted on a copy before the step runs on the real store: how
/// many items change status under valid-time order and the rule that a model only proposes a close, and why. It holds
/// counts and item ids, never a word of what a person said.
public struct LifecycleDryRun: Sendable, Equatable {
    public struct Change: Sendable, Equatable {
        public var item: Int64
        public var was: String
        public var now: String
        public var reason: String
    }

    /// The items the store holds.
    public var items: Int
    /// The events the store held before the step: the step adds one `open` event for each item.
    public var eventsBefore: Int
    public var changes: [Change]

    /// How many items change status for each reason.
    public var byReason: [String: Int] { changes.reduce(into: [:]) { $0[$1.reason, default: 0] += 1 } }

    /// Runs the step on a copy of the store in `directory`, reads what it logged, and deletes the copy. The store in
    /// `directory` is not opened, so its schema does not change; a copy of a store already at this step reports the
    /// changes that step logged.
    public static func run(onCopyOf directory: URL) throws -> LifecycleDryRun {
        let manager = FileManager.default
        let copy = manager.temporaryDirectory.appending(path: "lifecycle-dry-run-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: copy) }
        try manager.createDirectory(at: copy, withIntermediateDirectories: true)
        for name in ["workbench.sqlite", "workbench.sqlite-wal", "workbench.sqlite-shm"] {
            let source = directory.appending(path: name)
            if manager.fileExists(atPath: source.path) {
                try manager.copyItem(at: source, to: copy.appending(path: name))
            }
        }
        return try Store(directory: copy).queries.lifecycleRebuild()
    }
}

extension Queries {
    /// The items whose status the fact lifecycle step changed, from its log, with the counts of the store.
    func lifecycleRebuild() throws -> LifecycleDryRun {
        try reader.read { db in
            let items = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item") ?? 0
            let events = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item_event") ?? 0
            let changes = try Row.fetchAll(
                db, sql: "SELECT item_id, was, now, reason FROM status_change ORDER BY item_id"
            ).map { row in
                LifecycleDryRun.Change(
                    item: try row.value("item_id"), was: try row.value("was"), now: try row.value("now"),
                    reason: try row.value("reason"))
            }
            return LifecycleDryRun(items: items, eventsBefore: events - items, changes: changes)
        }
    }
}
