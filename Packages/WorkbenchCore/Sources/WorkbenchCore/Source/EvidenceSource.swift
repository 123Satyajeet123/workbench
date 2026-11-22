import Foundation
import Lines

/// A reader of one source that gives lines, not rows. It asks the person's policy before it reads, reads what is new
/// since the state the store kept, and returns what it saw. It writes nothing: `Store.ingest` writes the lines and
/// each cursor in one transaction. A chat that cannot be read is reported as a failure and does not stop the others.
public protocol EvidenceSource: Sendable {
    var descriptor: SourceDescriptor { get }

    /// One reading for each label (chat) read, and one failure for each label that could not be. `state` gives what
    /// the store kept for a label.
    func observe(state: @Sendable (String) throws -> ScanState, now: Date) async throws -> SourceRead
}

public enum EvidenceQuality: String, Sendable {
    /// The source named the line itself, and the name is unique.
    case stable
    /// The name needed a tie-break, such as a repeated stanza id.
    case derived
}

/// The id space of an old citation (`evidence_legacy.space`).
public enum LegacySpace: String, Sendable {
    case whatsAppRow = "wa_zpk"
}

/// What an old citation named: a row number of the source's own store.
public struct LegacyRef: Sendable, Equatable {
    public var space: LegacySpace
    public var ref: Int64

    public init(space: LegacySpace, ref: Int64) {
        self.space = space
        self.ref = ref
    }
}

/// One line a reader saw, with what the store keeps beside its text.
public struct ObservedLine: Sendable {
    public var line: Line
    public var quality: EvidenceQuality
    public var eventTime: UTCInstant?
    public var actor: String?
    /// The entity key of the message this one replies to.
    public var replyTo: EntityKey?
    /// The source's own id of the message in its container (a stanza id). A revoke erases by it, whatever the author
    /// part of the entity key is.
    public var messageRef: String?
    /// The old citation id of the row this line came from; set only while that id still means this row.
    public var legacy: LegacyRef?

    public init(
        line: Line, quality: EvidenceQuality = .stable, eventTime: UTCInstant? = nil, actor: String? = nil,
        replyTo: EntityKey? = nil, messageRef: String? = nil, legacy: LegacyRef? = nil
    ) {
        self.line = line
        self.quality = quality
        self.eventTime = eventTime
        self.actor = actor
        self.replyTo = replyTo
        self.messageRef = messageRef
        self.legacy = legacy
    }
}

/// How many rows of one source type a read saw, and how many had words.
public struct TypeCensus: Sendable, Equatable {
    public var rows = 0
    public var rowsWithText = 0

    public init(rows: Int = 0, rowsWithText: Int = 0) {
        self.rows = rows
        self.rowsWithText = rowsWithText
    }
}

/// What a reader saw in one container (one chat), under one grant.
public struct SourceReading: Sendable {
    public var grant: CaptureGrant
    /// What the person consented to: the chat as the policy names it.
    public var label: String
    public var container: String
    public var audience: AudienceDigest
    public var lines: [ObservedLine]
    /// Where the next read starts. Saved with the lines, or not at all. A source that reads what is on a page has none.
    public var cursorAfter: ScanCursor?
    /// Whether this read gave old citation ids to its lines, so the store notes that they were mapped.
    public var mapsLegacyRefs: Bool
    public var readerVersion: String
    /// Rows of each source type this read saw, by the source's type code.
    public var census: [Int: TypeCensus]
    /// Rows that should have been lines but had no name to key them by (no stanza id, or no author in a group).
    public var unkeyed: Int

    public init(
        grant: CaptureGrant, label: String, container: String, audience: AudienceDigest, lines: [ObservedLine],
        cursorAfter: ScanCursor?, mapsLegacyRefs: Bool = false, readerVersion: String,
        census: [Int: TypeCensus] = [:], unkeyed: Int = 0
    ) {
        self.grant = grant
        self.label = label
        self.container = container
        self.audience = audience
        self.lines = lines
        self.cursorAfter = cursorAfter
        self.mapsLegacyRefs = mapsLegacyRefs
        self.readerVersion = readerVersion
        self.census = census
        self.unkeyed = unkeyed
    }
}

/// A label that could not be read, and why.
public struct LabelFailure: Sendable {
    public var label: String
    public var error: any Error

    public init(label: String, error: any Error) {
        self.label = label
        self.error = error
    }
}

/// The result of one read of a source: what each readable chat gave, and what each unreadable chat failed with.
public struct SourceRead: Sendable {
    public var readings: [SourceReading]
    public var failures: [LabelFailure]

    public init(readings: [SourceReading] = [], failures: [LabelFailure] = []) {
        self.readings = readings
        self.failures = failures
    }
}
