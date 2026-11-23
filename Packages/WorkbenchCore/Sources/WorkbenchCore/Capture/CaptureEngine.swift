import Foundation

/// Turns what the sensors see into the activity worth keeping. Pure: the policy decides every item.
public struct CaptureEngine: Sendable {
    public enum SystemEvent: Sendable { case sleep, wake }

    /// How long without input makes the person idle: the threshold a `PresenceSource` is asked with.
    public var idleAfter: TimeInterval
    /// While the place stays the same, its text is kept again only when it changed and this much time passed.
    public var textInterval: TimeInterval
    /// While the place stays the same, a changed title is kept again after this much time. A terminal or editor shows
    /// its current task in the title.
    public var titleInterval: TimeInterval

    private var lastPlace: String?
    private var lastTitle: String?
    private var lastWindowAt = Date.distantPast
    private var lastText: String?
    private var lastTextAt = Date.distantPast
    private var idle = false

    public init(
        idleAfter: TimeInterval = 120, textInterval: TimeInterval = 60, titleInterval: TimeInterval = 60
    ) {
        self.idleAfter = idleAfter
        self.textInterval = textInterval
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
        _ snapshot: ScreenSnapshot, presence: PresenceState, policy: CapturePolicy, at now: Date
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
        let isIdle = presence != .active
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
        if policy.isEnabled(.screenText), !snapshot.text.isEmpty, textDue {
            if snapshot.text != lastText {
                out.append(
                    Activity(
                        at: now, kind: .text, app: snapshot.app, bundleID: snapshot.bundleID, title: snapshot.title,
                        document: address, text: snapshot.text))
                lastText = snapshot.text
            }
            lastTextAt = now
        }
        return ActivityBatch(out, grant: grant)
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

    static func titleLetters(_ title: String) -> String {
        String(String.UnicodeScalarView(title.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }

    /// The address without its query and fragment, which carry tokens and magic links. Nil when the app has none.
    static func address(_ document: String) -> String? {
        let kept = String(document.prefix { $0 != "?" && $0 != "#" })
        return kept.isEmpty ? nil : kept
    }
}
