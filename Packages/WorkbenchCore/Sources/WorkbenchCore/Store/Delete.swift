import Foundation

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

    fileprivate var clause: (sql: String, parameters: [SQLValue]) {
        var conditions = ["1 = 1"]
        var parameters: [SQLValue] = []
        if let id {
            conditions.append("id = ?")
            parameters.append(.int(id))
        }
        if let bundleID {
            conditions.append("bundle_id = ?")
            parameters.append(.text(bundleID))
        }
        if let domain {
            conditions.append("(document LIKE ? OR document LIKE ?)")
            parameters += [.text("%://\(domain)%"), .text("%://%.\(domain)%")]
        }
        if let from {
            conditions.append("ts >= ?")
            parameters.append(SQLValue(from))
        }
        if let to {
            conditions.append("ts < ?")
            parameters.append(SQLValue(to))
        }
        return (conditions.joined(separator: " AND "), parameters)
    }
}

extension Store {
    /// The one way captured data leaves the store: rows in one transaction, then their files.
    public func delete(_ selector: DeleteSelector) throws {
        let folders = try database.transaction {
            switch selector {
            case .activities(let filter):
                let clause = filter.clause
                try database.run(
                    """
                    DELETE FROM item WHERE source = 'screen' AND EXISTS (SELECT 1 FROM activity WHERE \(clause.sql)
                        AND activity.ts >= item.start_at AND activity.ts < item.end_at)
                    """, clause.parameters)
                try database.run("DELETE FROM activity WHERE \(clause.sql)", clause.parameters)
                return [String]()
            case .kind(let kind, let cutoff):
                return try remove(kind, before: cutoff ?? .distantFuture)
            case .machine(let task):
                try database.run("DELETE FROM item WHERE task = ?", [.text(task)])
                try database.run("DELETE FROM state WHERE key LIKE ? ESCAPE '\\'", [.text(Self.likePrefix(task))])
                if let row = try database.rows(
                    "SELECT id, name, template, spec FROM machine_now WHERE task = ?", [.text(task)]
                ).first, let id = row[0].integer,
                    let spec = try? Coding.value(HelperSpec.self, from: row[3].string ?? "")
                {
                    try change(
                        Machine(
                            id: id, name: row[1].string ?? "", template: row[2].string ?? "", spec: spec, state: .active
                        ),
                        name: row[1].string ?? "", spec: spec, state: .deleted)
                }
                return [String]()
            case .everything(let cutoff):
                return try SourceKind.allCases.flatMap { try remove($0, before: cutoff ?? .distantFuture) }
            }
        }
        for folder in folders { try removeFile(folder) }
        try database.run("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    private func remove(_ kind: SourceKind, before cutoff: Date) throws -> [String] {
        try database.run(
            "DELETE FROM item WHERE source = ? AND start_at < ?", [.text(kind.rawValue), SQLValue(cutoff)])
        switch kind {
        case .screen:
            try removeActivity(Activity.Kind.allCases.filter { $0 != .file }, before: cutoff)
        case .screenText: try removeActivity([.text], before: cutoff)
        case .files: try removeActivity([.file], before: cutoff)
        case .whatsapp: break
        case .call:
            let condition = "state != 'recording' AND started_at < ?"
            let folders = try database.rows("SELECT folder FROM recording WHERE \(condition)", [SQLValue(cutoff)])
            try database.run("DELETE FROM recording WHERE \(condition)", [SQLValue(cutoff)])
            return folders.compactMap { $0[0].string }
        }
        return []
    }

    private func removeActivity(_ kinds: [Activity.Kind], before cutoff: Date) throws {
        let marks = Array(repeating: "?", count: kinds.count).joined(separator: ",")
        try database.run(
            "DELETE FROM activity WHERE kind IN (\(marks)) AND ts < ?",
            kinds.map { .text($0.rawValue) } + [SQLValue(cutoff)])
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
