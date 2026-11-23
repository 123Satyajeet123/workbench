import Foundation

extension Schema {
    /// A recording names its service and meeting, and whether and why not it was transcribed. What was said is
    /// evidence lines (`SourceDescriptor.callTranscript`); the notes are the reply of the run that read them.
    static let calls = [
        "ALTER TABLE recording ADD COLUMN service TEXT",
        "ALTER TABLE recording ADD COLUMN title TEXT",
        "ALTER TABLE recording ADD COLUMN transcribed_at TEXT",
        "ALTER TABLE recording ADD COLUMN transcript_error TEXT",
    ]

    /// The guests of the calendar event a call overlaps, looked up once after it is saved: null until looked up.
    static let callGuests = [
        "ALTER TABLE recording ADD COLUMN guests TEXT CHECK(guests IS NULL OR json_valid(guests))"
    ]
}
