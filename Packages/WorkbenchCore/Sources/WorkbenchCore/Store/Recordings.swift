import Foundation

/// One recorded call: two audio files in its own folder under the store.
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

    /// The only way to start a recording: a live grant for a call.
    public func startRecording(app: String, bundleID: String, grant: CaptureGrant) throws -> Recording {
        try check(grant, kind: .call)
        let now = clock()
        let parent = directory.appending(path: Self.recordingsFolder)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try Self.restrict(parent, to: 0o700)
        let name = "\(Self.recordingsFolder)/\(UUID().uuidString)"
        try FileManager.default.createDirectory(at: directory.appending(path: name), withIntermediateDirectories: false)
        let id = try database.run(
            "INSERT INTO recording(app, bundle_id, folder, started_at, state) VALUES (?,?,?,?,'recording')",
            [.text(app), .text(bundleID), .text(name), SQLValue(now)])
        return Recording(
            id: id, app: app, bundleID: bundleID, folder: directory.appending(path: name), startedAt: now, endedAt: nil,
            state: .recording, error: nil)
    }

    public func finishRecording(_ id: Int64, error: String? = nil) throws {
        try database.run(
            "UPDATE recording SET state = ?, ended_at = ?, error = ? WHERE id = ? AND state = 'recording'",
            [.text(error == nil ? "saved" : "failed"), SQLValue(clock()), SQLValue(error), .int(id)])
    }

    /// A recording still open when the app starts was cut off: the app stopped during the call.
    public func closeInterruptedRecordings() throws {
        try database.run(
            "UPDATE recording SET state = 'failed', ended_at = ?, error = 'Workbench stopped during the call' WHERE state = 'recording'",
            [SQLValue(clock())])
    }
}

extension Queries {
    public func recordings() throws -> [Recording] {
        try database.rows(
            "SELECT id, app, bundle_id, folder, started_at, ended_at, state, error FROM recording ORDER BY id DESC"
        )
        .compactMap { row in
            guard let state = row[6].string.flatMap(Recording.State.init) else { return nil }
            return Recording(
                id: row[0].integer ?? 0, app: row[1].string ?? "", bundleID: row[2].string ?? "",
                folder: directory.appending(path: row[3].string ?? ""), startedAt: row[4].date ?? .distantPast,
                endedAt: row[5].date, state: state, error: row[7].string)
        }
    }
}
