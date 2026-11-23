import Foundation
import Kernel
import Lines

/// Where one stretch on a window ended, and what it showed. Kept in the `coordinate` of the stretch's line.
struct StretchPlace: Codable, Equatable {
    var end: Int64
    var app: String
    var title: String
    var document: String?
}

/// The screen as evidence lines (research 56 §1 Screen capture trigger row). A stretch on one window is one line, kept
/// when the stretch closes; the text a window showed is lines of its own. Both are the owner's own sight (`me`), named
/// by their content (`ephemeral`), and readable by the owner alone. The consent is the app's: one grant for each bundle
/// id.
public enum ScreenEvidence {
    static let windowReaderVersion = "screen-window 1"
    static let textReaderVersion = "screen-text 1"
    static let windowMark = "window:"
    static let textMark = "text:"

    private static var audience: AudienceDigest {
        AudienceDigest(owner: WhatsAppAudience.owner, members: [String]())
    }

    /// The line of one closed stretch, or nil when the stretch shows nothing or is too short to be a stay. An old stretch
    /// maps the id of the row that opened it, so a fact that cited that id finds the line.
    public static func reading(of session: ScreenSession, grant: CaptureGrant, mapsLegacyRef: Bool = false)
        -> SourceReading?
    {
        guard session.end.timeIntervalSince(session.start) >= Sessions.shortest, let label = grant.label,
            label == session.bundleID, let place = try? Coding.json(StretchPlace(session))
        else { return nil }
        let container = "\(label)@\(UTCInstant(session.start).milliseconds)"
        guard
            let line = try? Line.screen(
                container: container, texts: [session.words], readerVersion: windowReaderVersion
            ).first
        else { return nil }
        return SourceReading(
            grant: grant, label: label, container: container, audience: audience,
            lines: [
                ObservedLine(
                    line: line, quality: .ephemeral, eventTime: UTCInstant(session.start),
                    actor: WhatsAppAudience.owner, messageRef: windowMark + String(session.id),
                    legacy: mapsLegacyRef ? LegacyRef(space: .activityRow, ref: session.id) : nil, coordinate: place)
            ], cursorAfter: nil, readerVersion: windowReaderVersion)
    }

    /// The lines of the text one window walk gave: one line for each line of text, in reading order.
    public static func reading(ofText activity: Activity, id: Int64, grant: CaptureGrant) -> SourceReading? {
        guard activity.kind == .text, let label = grant.label, label == activity.bundleID,
            let text = activity.text
        else { return nil }
        let container = activity.document ?? label
        let rows = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let lines = try? Line.screen(container: container, texts: rows, readerVersion: textReaderVersion),
            !lines.isEmpty
        else { return nil }
        return SourceReading(
            grant: grant, label: label, container: container, audience: audience,
            lines: lines.map {
                ObservedLine(
                    line: $0, quality: .ephemeral, eventTime: UTCInstant(activity.at), actor: WhatsAppAudience.owner,
                    messageRef: textMark + String(id), coordinate: activity.title.isEmpty ? nil : activity.title)
            }, cursorAfter: nil, readerVersion: textReaderVersion)
    }
}

extension StretchPlace {
    init(_ session: ScreenSession) {
        self.init(
            end: UTCInstant(session.end).milliseconds, app: session.app, title: session.title,
            document: session.document)
    }
}

extension ScreenSession {
    func isSameWindow(as other: ScreenSession) -> Bool {
        app == other.app && bundleID == other.bundleID && title == other.title && document == other.document
    }

    /// What the stretch shows, on one line: the app, the window's title and its address.
    var words: String { [app, title, document ?? ""].filter { !$0.isEmpty }.joined(separator: " — ") }

    public var evidence: Evidence {
        Evidence(
            id: id, start: start, end: end, line: words, quotable: [title, document ?? ""], lineID: lineID,
            provenance: provenance)
    }
}

/// What the capture loop keeps of the screen: it follows the activity log, and gives the lines to write for each batch
/// of activity and for the stretches the batch closed. A closed stretch is held until its window can no longer be
/// returned to within `Sessions.joinGap`, so a return joins it and flicker gives one line. A stretch shorter than
/// `Sessions.shortest` is a pass through a window and is never held.
public struct ScreenKeeper: Sendable {
    private var stretches = ScreenStretches()
    private var held: ScreenSession?

    public init() {}

    /// The writes for `batch`, whose rows were stored under `ids` in the same order. Each write names its source. A stretch
    /// is written under the app's own consent as `policy` gives it at `now`: a consent withdrawn since gives no grant,
    /// and the stretch is dropped.
    public mutating func writes(
        for batch: ActivityBatch, ids: [Int64], policy: CapturePolicy, at now: Date
    ) -> [ScreenWrite] {
        var ready = releasedBy(now)
        var writes: [ScreenWrite] = []
        for (activity, id) in zip(batch.activities, ids) {
            if let closed = stretches.feed(activity, id: id) { ready += hold(closed) }
            if activity.kind == .text, policy.isEnabled(.screenText),
                let grant = Self.grant(for: activity.bundleID, policy: policy, at: now),
                let reading = ScreenEvidence.reading(ofText: activity, id: id, grant: grant)
            {
                writes.append(ScreenWrite(reading: reading, descriptor: .screenText))
            }
        }
        return ready.compactMap { Self.write($0, policy: policy, at: now) } + writes
    }

    /// The writes for a tick with no activity: the held stretch whose window was not returned to in time.
    public mutating func writes(idleAt now: Date, policy: CapturePolicy) -> [ScreenWrite] {
        releasedBy(now).compactMap { Self.write($0, policy: policy, at: now) }
    }

    /// The writes when capture pauses or stops, or the app quits: the open stretch ends at `now`, and the held one is
    /// let go. Each is kept only if the app's consent still holds. A pause or a private hour is not a withdrawal, so the
    /// policy is asked as if capture were on: a switch turned off or an app denied drops the stretch.
    public mutating func writes(stoppingAt now: Date, policy: CapturePolicy) -> [ScreenWrite] {
        var running = policy
        running.mode = .on
        let closed = stretches.close(at: now).map { hold($0) } ?? []
        let ready = closed + (held.map { [$0] } ?? [])
        held = nil
        return ready.compactMap { Self.write($0, policy: running, at: now) }
    }

    /// Holds a closed stretch. Returns the stretch to write now, if any: the one held before, when `closed` is another
    /// window or too late to join it.
    private mutating func hold(_ closed: ScreenSession) -> [ScreenSession] {
        guard closed.end.timeIntervalSince(closed.start) >= Sessions.shortest else { return [] }
        guard let earlier = held else {
            held = closed
            return []
        }
        if earlier.isSameWindow(as: closed), closed.start.timeIntervalSince(earlier.end) <= Sessions.joinGap {
            held?.end = closed.end
            return []
        }
        held = closed
        return [earlier]
    }

    private mutating func releasedBy(_ now: Date) -> [ScreenSession] {
        guard let earlier = held, now.timeIntervalSince(earlier.end) > Sessions.joinGap else { return [] }
        held = nil
        return [earlier]
    }

    private static func write(_ session: ScreenSession, policy: CapturePolicy, at now: Date) -> ScreenWrite? {
        guard let grant = grant(for: session.bundleID, policy: policy, at: now),
            let reading = ScreenEvidence.reading(of: session, grant: grant)
        else { return nil }
        return ScreenWrite(reading: reading, descriptor: .screenWindow)
    }

    private static func grant(for bundleID: String, policy: CapturePolicy, at now: Date) -> CaptureGrant? {
        policy.authorize(CaptureRequest(kind: .screen, label: bundleID), at: now).grant
    }
}

/// One reading of the screen and the source that stores it.
public struct ScreenWrite: Sendable {
    public var reading: SourceReading
    public var descriptor: SourceDescriptor
}

extension ScreenSession {
    /// The stretch a stored line is. Nil for a line that is no stretch.
    init?(_ line: StoredLine) {
        guard !line.isTombstone, let start = line.time,
            let place = line.coordinate.flatMap({ try? Coding.value(StretchPlace.self, from: $0) }),
            let label = line.grantID.split(separator: ":", maxSplits: 1).last
        else { return nil }
        self.init(
            id: line.number, start: start, end: Date(timeIntervalSince1970: Double(place.end) / 1000),
            app: place.app, bundleID: String(label), title: place.title, document: place.document,
            lineID: line.lineID, provenance: line.provenance)
    }
}

extension Queries {
    /// The stretches that began in `start..<end`, oldest first.
    public func screenSessions(from start: Date, to end: Date) throws -> [ScreenSession] {
        let prefix = Store.grantID(kind: .screen, label: "")
        return try reader.read { db in
            try StoredLine.fetchAll(
                db,
                sql: """
                    SELECT e.id AS number, \(StoredLine.columns) FROM evidence e
                    WHERE substr(e.grant_id, 1, length(?)) = ? AND substr(e.message_ref, 1, length(?)) = ?
                        AND e.event_time >= ? AND e.event_time < ?
                    ORDER BY e.event_time, e.id
                    """,
                arguments: [
                    prefix, prefix, ScreenEvidence.windowMark, ScreenEvidence.windowMark,
                    start.millisecondsSince1970, end.millisecondsSince1970,
                ]
            ).compactMap(ScreenSession.init)
        }
    }
}
