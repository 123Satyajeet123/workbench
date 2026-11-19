import Foundation
import GRDB

public enum DeleteSelector: Sendable {
    /// Screen and file activity that matches every field the filter names, and the screen items over its time.
    case activities(ActivityFilter)
    /// What one kind of source produced before the cutoff (all of it when nil): its activity, its recordings, and
    /// the items helpers read from it. A call still being recorded stays.
    case kind(SourceKind, before: Date?)
    /// One machine: its items and their marks, its saved settings, and a deleted state. Its runs stay in the meter.
    case machine(String)
    /// Every kind. The consent history and the record of model runs hold no captured content, and stay.
    case everything(before: Date?)
}

public struct ActivityFilter: Sendable {
    public var id: Int64?
    public var bundleID: String?
    /// A site and its subdomains.
    public var domain: String?
    public var from: Date?
    public var to: Date?

    public init(
        id: Int64? = nil, bundleID: String? = nil, domain: String? = nil, from: Date? = nil, to: Date? = nil
    ) {
        self.id = id
        self.bundleID = bundleID
        self.domain = domain
        self.from = from
        self.to = to
    }

    fileprivate var clause: (sql: String, arguments: StatementArguments) {
        var conditions = ["1 = 1"]
        var arguments: [any DatabaseValueConvertible] = []
        if let id {
            conditions.append("id = ?")
            arguments.append(id)
        }
        if let bundleID {
            conditions.append("bundle_id = ?")
            arguments.append(bundleID)
        }
        if let domain {
            conditions.append("(document LIKE ? OR document LIKE ?)")
            arguments += ["%://\(domain)%", "%://%.\(domain)%"]
        }
        if let from {
            conditions.append("ts >= ?")
            arguments.append(from.stored)
        }
        if let to {
            conditions.append("ts < ?")
            arguments.append(to.stored)
        }
        return (conditions.joined(separator: " AND "), StatementArguments(arguments))
    }
}

extension Store {
    /// How often the log is checkpointed when a reader still holds it, before the delete reports failure.
    static let checkpointAttempts = 3

    /// The one way captured data leaves the store: rows in one transaction, then their files, then the log. The
    /// delete succeeds only when the write-ahead log no longer holds the deleted text.
    public func delete(_ selector: DeleteSelector) throws {
        let folders = try writer.write { db in
            switch selector {
            case .activities(let filter):
                let clause = filter.clause
                try db.execute(
                    sql: """
                        DELETE FROM item WHERE source = 'screen' AND EXISTS (SELECT 1 FROM activity WHERE \(clause.sql)
                            AND activity.ts >= item.start_at AND activity.ts < item.end_at)
                        """, arguments: clause.arguments)
                try db.execute(sql: "DELETE FROM activity WHERE \(clause.sql)", arguments: clause.arguments)
                return [String]()
            case .kind(let kind, let cutoff):
                return try remove(db, kind, before: cutoff ?? .distantFuture)
            case .machine(let task):
                try db.execute(sql: "DELETE FROM item WHERE task = ?", arguments: [task])
                try db.execute(
                    sql: "DELETE FROM state WHERE key LIKE ? ESCAPE '\\'", arguments: [Self.likePrefix(task)])
                let machines = try db.fetch(
                    "machine_now", "SELECT id, name, template, spec, state FROM machine_now WHERE task = ?", [task],
                    as: Machine.init(row:))
                if let machine = machines.first {
                    try change(db, machine, name: machine.name, spec: machine.spec, state: .deleted)
                }
                return [String]()
            case .everything(let cutoff):
                return try SourceKind.allCases.flatMap { try remove(db, $0, before: cutoff ?? .distantFuture) }
            }
        }
        for folder in folders { try removeFile(folder) }
        try truncateLog()
    }

    /// Empties the write-ahead log. A reader that still holds it makes SQLite report busy. The delete waits, tries
    /// again, then throws, because the deleted text would still be on disk.
    private func truncateLog() throws {
        for _ in 0..<Self.checkpointAttempts {
            do {
                _ = try writer.writeWithoutTransaction { db in try db.checkpoint(.truncate) }
                return
            } catch let error as DatabaseError where error.resultCode == .SQLITE_BUSY {
                continue
            }
        }
        throw StoreError.logNotTruncated
    }

    private func remove(_ db: Database, _ kind: SourceKind, before cutoff: Date) throws -> [String] {
        try db.execute(
            sql: "DELETE FROM item WHERE source = ? AND start_at < ?", arguments: [kind.rawValue, cutoff.stored])
        switch kind {
        case .screen:
            try removeActivity(db, Activity.Kind.allCases.filter { $0 != .file }, before: cutoff)
        case .screenText: try removeActivity(db, [.text, .page], before: cutoff)
        case .files: try removeActivity(db, [.file], before: cutoff)
        case .whatsapp: break
        case .call:
            let condition = "state != 'recording' AND started_at < ?"
            let folders = try String.fetchAll(
                db, sql: "SELECT folder FROM recording WHERE \(condition)", arguments: [cutoff.stored])
            try db.execute(sql: "DELETE FROM recording WHERE \(condition)", arguments: [cutoff.stored])
            return folders
        }
        return []
    }

    private func removeActivity(_ db: Database, _ kinds: [Activity.Kind], before cutoff: Date) throws {
        let marks = Array(repeating: "?", count: kinds.count).joined(separator: ",")
        try db.execute(
            sql: "DELETE FROM activity WHERE kind IN (\(marks)) AND ts < ?",
            arguments: StatementArguments(kinds.map(\.rawValue)) + [cutoff.stored])
    }

    private static func likePrefix(_ task: String) -> String {
        task.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + ".%"
    }

    private func removeFile(_ path: String) throws {
        do {
            try FileManager.default.removeItem(at: directory.appending(path: path))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            throw StoreError.fileNotRemoved(path)
        }
    }
}
