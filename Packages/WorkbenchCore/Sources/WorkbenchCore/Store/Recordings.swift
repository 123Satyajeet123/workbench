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
    public var service: String?
    public var title: String?

    public var source: CallSource { CallSource(service: service ?? app, title: title ?? "") }
}

extension Store {
    static let recordingsFolder = "recordings"
    static let recordingsPlaceKey = "calls.folder"

    public var defaultRecordingsPlace: URL { directory.appending(path: Self.recordingsFolder) }

    public func recordingsPlace() throws -> URL? {
        try queries.state(forKey: Self.recordingsPlaceKey).flatMap { $0.isEmpty ? nil : URL(filePath: $0) }
    }

    public func setRecordingsPlace(_ place: URL?) throws {
        try saveState(place?.path ?? "", forKey: Self.recordingsPlaceKey)
    }

    func resolve(_ stored: String) -> URL { Self.resolve(stored, in: directory) }

    static func resolve(_ stored: String, in directory: URL) -> URL {
        stored.hasPrefix("/") ? URL(filePath: stored) : directory.appending(path: stored)
    }

    public func startRecording(
        app: String, bundleID: String, source: CallSource? = nil, grant: CaptureGrant
    ) throws -> Recording {
        try check(grant, kind: .call)
        let now = clock()
        let name: String
        if let place = try recordingsPlace() {
            try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
            name = place.appending(path: UUID().uuidString).path
        } else {
            let parent = defaultRecordingsPlace
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try Self.restrict(parent, to: 0o700)
            name = "\(Self.recordingsFolder)/\(UUID().uuidString)"
        }
        try FileManager.default.createDirectory(at: resolve(name), withIntermediateDirectories: false)
        try Self.restrict(resolve(name), to: 0o700)
        let id = try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO recording(app, bundle_id, folder, started_at, state, service, title)
                    VALUES (?,?,?,?,'recording',?,?)
                    """, arguments: [app, bundleID, name, now.stored, source?.service, source?.title])
            return db.lastInsertedRowID
        }
        return Recording(
            id: id, app: app, bundleID: bundleID, folder: resolve(name), startedAt: now, endedAt: nil,
            state: .recording, error: nil, service: source?.service, title: source?.title)
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
                """
                SELECT id, app, bundle_id, folder, started_at, ended_at, state, error, service, title
                FROM recording ORDER BY id DESC
                """
            ) { row in
                Recording(
                    id: try row.value("id"), app: try row.value("app"), bundleID: try row.value("bundle_id"),
                    folder: Store.resolve(try row.value("folder"), in: directory),
                    startedAt: try row.date("started_at"), endedAt: try row.optionalDate("ended_at"),
                    state: try row.enumeration("state"), error: try row.optionalValue("error"),
                    service: try row.optionalValue("service"), title: try row.optionalValue("title"))
            }
        }
    }
}
