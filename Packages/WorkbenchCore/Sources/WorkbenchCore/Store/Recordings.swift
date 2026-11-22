import Foundation
import GRDB

public struct Recording: Sendable, Equatable, Identifiable {
    public enum State: String, Sendable, CaseIterable { case recording, saved, failed }

    public var id: Int64
    public var app: String
    public var bundleID: String
    public var folder: URL
    public var startedAt: Date
    public var endedAt: Date?
    public var state: State
    public var error: String?
}

extension Store {
    static let recordingsFolder = "recordings"

    public func startRecording(app: String, bundleID: String, grant: CaptureGrant) throws -> Recording {
        try check(grant, kind: .call)
        let now = clock()
        let parent = directory.appending(path: Self.recordingsFolder)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try Self.restrict(parent, to: 0o700)
        let name = "\(Self.recordingsFolder)/\(UUID().uuidString)"
        try FileManager.default.createDirectory(at: directory.appending(path: name), withIntermediateDirectories: false)
        let id = try writer.write { db in
            try db.execute(
                sql: "INSERT INTO recording(app, bundle_id, folder, started_at, state) VALUES (?,?,?,?,'recording')",
                arguments: [app, bundleID, name, now.stored])
            return db.lastInsertedRowID
        }
        return Recording(
            id: id, app: app, bundleID: bundleID, folder: directory.appending(path: name), startedAt: now, endedAt: nil,
            state: .recording, error: nil)
    }

    public func finishRecording(_ id: Int64, error: String? = nil) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE recording SET state = ?, ended_at = ?, error = ? WHERE id = ? AND state = 'recording'",
                arguments: [error == nil ? "saved" : "failed", clock().stored, error, id])
        }
    }

    public func closeInterruptedRecordings() throws {
        try writer.write { db in
            try db.execute(
                sql:
                    "UPDATE recording SET state = 'failed', ended_at = ?, error = 'Workbench stopped during the call' WHERE state = 'recording'",
                arguments: [clock().stored])
        }
    }
}

extension Queries {
    public func recordings() throws -> [Recording] {
        try reader.read { db in
            try db.fetch(
                "recording",
                "SELECT id, app, bundle_id, folder, started_at, ended_at, state, error FROM recording ORDER BY id DESC"
            ) { row in
                Recording(
                    id: try row.value("id"), app: try row.value("app"), bundleID: try row.value("bundle_id"),
                    folder: directory.appending(path: try row.value("folder") as String),
                    startedAt: try row.date("started_at"), endedAt: try row.optionalDate("ended_at"),
                    state: try row.enumeration("state"), error: try row.optionalValue("error"))
            }
        }
    }
}
