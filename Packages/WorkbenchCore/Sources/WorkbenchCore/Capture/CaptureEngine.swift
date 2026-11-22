import Foundation

public struct CaptureEngine: Sendable {
    public enum FileChange: String, Sendable { case create, modify, rename }
    public enum SystemEvent: Sendable { case sleep, wake }

    public var idleAfter: TimeInterval
    public var textInterval: TimeInterval
    public var fileWindow: TimeInterval
    public var filesPerWindow = 60
    public var titleInterval: TimeInterval

    private var lastPlace: String?
    private var lastTitle: String?
    private var lastWindowAt = Date.distantPast
    private var lastText: String?
    private var lastTextAt = Date.distantPast
    private var idle = false
    private var lastSeen: [String: Date] = [:]
    private var fileWindowStart = Date.distantPast
    private var filesInWindow = 0

    public init(
        idleAfter: TimeInterval = 120, textInterval: TimeInterval = 60, fileWindow: TimeInterval = 60,
        titleInterval: TimeInterval = 60
    ) {
        self.idleAfter = idleAfter
        self.textInterval = textInterval
        self.fileWindow = fileWindow
        self.titleInterval = titleInterval
    }

    public func wantsText(for snapshot: ScreenSnapshot, policy: CapturePolicy, at now: Date) -> Bool {
        guard policy.isEnabled(.screenText), case .keep = policy.verdict(for: snapshot, at: now) else { return false }
        return snapshot.place != lastPlace || now.timeIntervalSince(lastTextAt) >= textInterval
    }

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
        if now.timeIntervalSince(fileWindowStart) >= fileWindow {
            fileWindowStart = now
            filesInWindow = 0
        }
        guard filesInWindow < filesPerWindow else { return nil }
        filesInWindow += 1
        if lastSeen.count > 2048 { lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < fileWindow } }
        return ActivityBatch(
            [Activity(at: now, kind: .file, title: change.rawValue, document: URL(filePath: path).absoluteString)],
            grant: grant)
    }

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

    static func address(_ document: String) -> String? {
        let kept = String(document.prefix { $0 != "?" && $0 != "#" })
        return kept.isEmpty ? nil : kept
    }
}
