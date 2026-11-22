import Foundation
import GRDB

public enum DeleteSelector: Sendable {
    case activities(ActivityFilter)
    case kind(SourceKind, before: Date?)
    case machine(String)
    case everything(before: Date?)
}

public struct ActivityFilter: Sendable {
    public var id: Int64?
    public var bundleID: String?
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
    static let checkpointAttempts = 3

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
                try removeRunText(
                    db, holding: [.screen, .screenText, .files], from: filter.from, before: filter.to)
                try removeSummaries(db, holding: [.screen, .screenText, .files], before: .distantFuture)
                return [String]()
            case .kind(let kind, let cutoff):
                return try remove(db, kind, before: cutoff ?? .distantFuture)
            case .machine(let task):
                let tasks = [task, Trial.task(of: task)]
                try db.execute(sql: "DELETE FROM item WHERE task IN (?,?)", arguments: StatementArguments(tasks))
                try removeRunText(db, tasks: tasks + [Summarizer.task])
                try removeSummaries(db, tasks: tasks)
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
                try removeRunText(db, before: cutoff)
                try removeTyped(db, before: cutoff)
                return try SourceKind.captured.flatMap { try remove(db, $0, before: cutoff ?? .distantFuture) }
            }
        }
        for folder in folders { try removeFile(folder) }
        try truncateLog()
    }

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

    private func removeTyped(_ db: Database, before cutoff: Date?) throws {
        let closed = cutoff == nil ? "" : "AND status_kind = 'close'"
        try db.execute(
            sql: """
                DELETE FROM item WHERE source = ? AND start_at < ? AND id IN (
                    SELECT id FROM item_mark LEFT JOIN item_status ON item_status.item_id = item_mark.id
                    WHERE 1 = 1 \(closed))
                """, arguments: [SourceKind.typed.rawValue, (cutoff ?? .distantFuture).stored])
        try removeRunText(db, holding: [.typed], before: cutoff)
        try removeSummaries(db, holding: [.typed], before: cutoff ?? .distantFuture)
    }

    private func remove(_ db: Database, _ kind: SourceKind, before cutoff: Date) throws -> [String] {
        guard kind != .typed else { return [] }
        try db.execute(
            sql: "DELETE FROM item WHERE source = ? AND start_at < ?", arguments: [kind.rawValue, cutoff.stored])
        try removeRunText(db, holding: [kind], before: cutoff)
        try removeSummaries(db, holding: [kind], before: cutoff)
        switch kind {
        case .screen:
            try removeActivity(db, Activity.Kind.allCases.filter { $0 != .file }, before: cutoff)
        case .screenText: try removeActivity(db, [.text, .page], before: cutoff)
        case .files: try removeActivity(db, [.file], before: cutoff)
        case .whatsapp, .typed: break
        case .mail:
            try db.execute(sql: "DELETE FROM mail_part WHERE seen_at < ?", arguments: [cutoff.stored])
            try db.execute(sql: "DELETE FROM mail_open WHERE day < ?", arguments: [String(cutoff.stored.prefix(10))])
        case .calendar, .web: break
        case .call:
            let condition = "state != 'recording' AND started_at < ?"
            let folders = try String.fetchAll(
                db, sql: "SELECT folder FROM recording WHERE \(condition)", arguments: [cutoff.stored])
            try db.execute(sql: "DELETE FROM recording WHERE \(condition)", arguments: [cutoff.stored])
            return folders
        }
        return []
    }

    private func removeRunText(
        _ db: Database, holding kinds: [SourceKind]? = nil, tasks: [String]? = nil, from: Date? = nil,
        before: Date? = nil
    ) throws {
        var conditions = ["1 = 1"]
        var arguments: [any DatabaseValueConvertible] = []
        if let kinds {
            let names = kinds.map(\.rawValue) + [RunText.unknownKind]
            let marks = databaseQuestionMarks(count: names.count)
            conditions.append("EXISTS (SELECT 1 FROM json_each(run_text.kinds) WHERE value IN (\(marks)))")
            arguments += names
        }
        if let tasks {
            conditions.append("run.task IN (\(databaseQuestionMarks(count: tasks.count)))")
            arguments += tasks
        }
        if let from {
            conditions.append("run.started_at >= ?")
            arguments.append(from.stored)
        }
        if let before {
            conditions.append("run.started_at < ?")
            arguments.append(before.stored)
        }
        try db.execute(
            sql: """
                DELETE FROM run_text WHERE run_id IN (
                    SELECT run.id FROM run JOIN run_text ON run_text.run_id = run.id
                    WHERE \(conditions.joined(separator: " AND ")))
                """, arguments: StatementArguments(arguments))
    }

    private func removeActivity(_ db: Database, _ kinds: [Activity.Kind], before cutoff: Date) throws {
        let marks = databaseQuestionMarks(count: kinds.count)
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
