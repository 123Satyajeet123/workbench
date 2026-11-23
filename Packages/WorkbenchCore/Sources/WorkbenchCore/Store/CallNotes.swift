import Foundation
import GRDB

public struct CallNote: Sendable, Equatable {
    public var transcript: [CallLine]?
    public var transcriptError: String?
    public var summary: CallSummary?
    public var summaryError: String?
    public var run: RunID?

    public init(
        transcript: [CallLine]? = nil, transcriptError: String? = nil, summary: CallSummary? = nil,
        summaryError: String? = nil, run: RunID? = nil
    ) {
        self.transcript = transcript
        self.transcriptError = transcriptError
        self.summary = summary
        self.summaryError = summaryError
        self.run = run
    }
}

extension Store {
    public func saveTranscript(of recording: Int64, lines: [CallLine]?, error: String? = nil) throws {
        let json = try lines.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO call_note(recording_id, transcript, transcript_error, updated_at) VALUES (?,?,?,?)
                    ON CONFLICT(recording_id) DO UPDATE SET transcript = excluded.transcript,
                        transcript_error = excluded.transcript_error, summary = NULL, summary_error = NULL,
                        run_id = NULL, updated_at = excluded.updated_at
                    """, arguments: [recording, json, error, clock().stored])
        }
    }

    public func saveSummary(of recording: Int64, summary: CallSummary?, run: RunID?, error: String? = nil) throws {
        let json = try summary.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        try writer.write { db in
            try db.execute(
                sql: """
                    UPDATE call_note SET summary = ?, summary_error = ?, run_id = ?, updated_at = ?
                    WHERE recording_id = ?
                    """, arguments: [json, error, run, clock().stored, recording])
        }
    }

    public func forgetNote(of recording: Int64) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM call_note WHERE recording_id = ?", arguments: [recording])
        }
    }
}

extension Queries {
    public func callNotes() throws -> [Int64: CallNote] {
        try reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT recording_id, transcript, transcript_error, summary, summary_error, run_id FROM call_note")
            return Dictionary(
                uniqueKeysWithValues: try rows.map { row in
                    let decoder = JSONDecoder()
                    let transcript = try (row["transcript"] as String?).map {
                        try decoder.decode([CallLine].self, from: Data($0.utf8))
                    }
                    let summary = try (row["summary"] as String?).map {
                        try decoder.decode(CallSummary.self, from: Data($0.utf8))
                    }
                    return (
                        row["recording_id"] as Int64,
                        CallNote(
                            transcript: transcript, transcriptError: row["transcript_error"], summary: summary,
                            summaryError: row["summary_error"], run: row["run_id"])
                    )
                })
        }
    }
}
