import Foundation

/// Turns what the sensors see into the activity worth keeping. Pure: the policy decides every item.
public struct CaptureEngine: Sendable {
    public enum FileChange: String, Sendable { case create, modify, rename }
    public enum SystemEvent: Sendable { case sleep, wake }

    public var idleAfter: TimeInterval
    /// While the place stays the same, its text is kept again only when it changed and this much time passed.
    public var textInterval: TimeInterval
    /// One row per file per this many seconds.
    public var fileWindow: TimeInterval
    /// While the place stays the same, a changed title is kept again after this much time. A terminal or editor shows
    /// its current task in the title.
    public var titleInterval: TimeInterval

    private var lastPlace: String?
    private var lastTitle: String?
    private var lastWindowAt = Date.distantPast
    private var lastText: String?
    private var lastTextAt = Date.distantPast
    private var idle = false
    private var lastSeen: [String: Date] = [:]

    public init(
        idleAfter: TimeInterval = 120, textInterval: TimeInterval = 60, fileWindow: TimeInterval = 60,
        titleInterval: TimeInterval = 60
    ) {
        self.idleAfter = idleAfter
        self.textInterval = textInterval
        self.fileWindow = fileWindow
        self.titleInterval = titleInterval
    }

    /// The text walk costs the watched app work, so it runs only for a window the policy keeps, on a new place or once
    /// per interval.
    public func wantsText(for snapshot: ScreenSnapshot, policy: CapturePolicy, at now: Date) -> Bool {
        guard policy.isEnabled(.screenText), case .keep = policy.verdict(for: snapshot, at: now) else { return false }
        return snapshot.place != lastPlace || now.timeIntervalSince(lastTextAt) >= textInterval
    }

    /// Nil when capture is off, paused, private or the screen source is switched off: then nothing is kept at all.
    public mutating func observe(
        _ snapshot: ScreenSnapshot, idleSeconds: TimeInterval, policy: CapturePolicy, at now: Date
    ) -> ActivityBatch? {
        let verdict = policy.verdict(for: snapshot, at: now)
        let grant: CaptureGrant
        switch verdict {
        case .stop:
            resetScreen()
            return nil
        case .keep(let granted), .hide(let granted): grant = granted
        }
        var out: [Activity] = []
        let isIdle = idleSeconds >= idleAfter
        if isIdle != idle {
            idle = isIdle
            out.append(Activity(at: now, kind: isIdle ? .idle : .active))
        }
        if isIdle { return ActivityBatch(out, grant: grant) }

        let placeChanged = snapshot.place != lastPlace
        lastPlace = snapshot.place
        guard case .keep = verdict else {
            lastText = nil
            if placeChanged { out.append(Activity(at: now, kind: .skipped)) }
            return ActivityBatch(out, grant: grant)
        }
        let address = Self.address(snapshot.document)
        let title = Self.titleLetters(snapshot.title)
        let titleChanged = title != lastTitle && now.timeIntervalSince(lastWindowAt) >= titleInterval
        if placeChanged || titleChanged {
            lastTitle = title
            lastWindowAt = now
            out.append(
                Activity(
                    at: now, kind: .window, app: snapshot.app, bundleID: snapshot.bundleID, title: snapshot.title,
                    document: address))
        }
        let textDue = placeChanged || now.timeIntervalSince(lastTextAt) >= textInterval
        if policy.isEnabled(.screenText), !snapshot.text.isEmpty, snapshot.text != lastText, textDue {
            out.append(
                Activity(
                    at: now, kind: .text, app: snapshot.app, bundleID: snapshot.bundleID, title: snapshot.title,
                    document: address, text: snapshot.text))
            lastText = snapshot.text
            lastTextAt = now
        }
        return ActivityBatch(out, grant: grant)
    }

    public mutating func observe(_ change: FileChange, path: String, policy: CapturePolicy, at now: Date)
        -> ActivityBatch?
    {
        guard case .keep(let grant) = policy.verdict(forFile: path, at: now) else { return nil }
        if let last = lastSeen[path], now.timeIntervalSince(last) < fileWindow { return nil }
        lastSeen[path] = now
        if lastSeen.count > 2048 { lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < fileWindow } }
        return ActivityBatch(
            [Activity(at: now, kind: .file, title: change.rawValue, document: URL(filePath: path).absoluteString)],
            grant: grant)
    }

    /// Sleep and wake bound a gap in the record. After either, the next window is written again.
    public mutating func system(_ event: SystemEvent, policy: CapturePolicy, at now: Date) -> ActivityBatch? {
        resetScreen()
        guard let grant = policy.authorize(CaptureRequest(kind: .screen), at: now).grant else { return nil }
        return ActivityBatch([Activity(at: now, kind: event == .sleep ? .sleep : .wake)], grant: grant)
    }

    private mutating func resetScreen() {
        lastPlace = nil
        lastTitle = nil
        lastWindowAt = .distantPast
        lastText = nil
        lastTextAt = .distantPast
        idle = false
    }

    /// The letters and digits of a title: a spinner or a counter glyph in front of the same words is the same title.
    static func titleLetters(_ title: String) -> String {
        String(String.UnicodeScalarView(title.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }

    /// The address without its query and fragment, which carry tokens and magic links. Nil when the app has none.
    static func address(_ document: String) -> String? {
        let kept = String(document.prefix { $0 != "?" && $0 != "#" })
        return kept.isEmpty ? nil : kept
    }
}
