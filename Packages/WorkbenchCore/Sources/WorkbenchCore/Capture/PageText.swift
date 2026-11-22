import Foundation

/// The text of a web page as the person saw it, sent by the Workbench browser extension. Chromium browsers do not show
/// page text to a read-only Accessibility client (measured on Brave, 2026-11-19), so the extension reads it in the
/// page instead. A page is screen text from a browser: the same switch, private rules and deletion apply.
public struct WebPage: Codable, Sendable, Equatable {
    public var browser: String
    public var url: String
    public var title: String
    public var text: String

    public init(browser: String, url: String, title: String, text: String) {
        self.browser = browser
        self.url = url
        self.title = title
        self.text = text
    }

    public func batch(policy: CapturePolicy, at now: Date) -> ActivityBatch? {
        guard policy.isEnabled(.screenText), CapturePolicy.browserBundleIDs.contains(browser), !text.isEmpty,
            !CapturePolicy.isSite(url, in: [MailContext.site])
        else { return nil }
        let snapshot = ScreenSnapshot(
            app: browserName, bundleID: browser, windowID: 0, document: url, title: title, text: text)
        guard case .keep(let grant) = policy.verdict(for: snapshot, at: now) else { return nil }
        return ActivityBatch(
            [
                Activity(
                    at: now, kind: .page, app: browserName, bundleID: browser, title: title,
                    document: CaptureEngine.address(url), text: text)
            ], grant: grant)
    }

    private var browserName: String {
        [
            "com.brave.Browser": "Brave Browser", "com.google.Chrome": "Google Chrome",
            "company.thebrowser.Browser": "Arc", "com.microsoft.edgemac": "Microsoft Edge",
        ][browser] ?? browser
    }
}

extension WebPage {
    public static let budget = 200_000

    public static func site(_ typed: String) -> String? {
        guard let host = CapturePolicy.host(of: typed.trimmingCharacters(in: .whitespacesAndNewlines)),
            host.contains(".")
        else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func reading(_ activities: [Activity], sites: [String], budget: Int = budget) -> (
        pages: [Activity], leftOut: Int
    ) {
        let named = Set(sites)
        var seen = Set<String>()
        var pages: [Activity] = []
        var used = 0
        var leftOut = 0
        for activity in activities.sorted(by: { $0.at < $1.at })
        where activity.kind == .page {
            guard let text = activity.text, let document = activity.document,
                CapturePolicy.isSite(document, in: named), seen.insert(document + "\n" + text).inserted
            else { continue }
            guard used + text.count <= budget else {
                leftOut += 1
                continue
            }
            used += text.count
            pages.append(activity)
        }
        return (pages, leftOut)
    }
}

public enum NativeMessage {
    public static let maximumLength = 1024 * 1024

    public enum Failure: Error, Equatable {
        case truncated
        case tooLong(Int)
    }

    public static func first(in data: Data) throws -> (message: Data, consumed: Int)? {
        guard !data.isEmpty else { return nil }
        guard data.count >= 4 else { throw Failure.truncated }
        let length = data.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        guard length <= maximumLength else { throw Failure.tooLong(length) }
        guard data.count >= 4 + length else { throw Failure.truncated }
        let start = data.startIndex + 4
        return (data[start..<start + length], 4 + length)
    }

    public static func frame(_ message: Data) -> Data {
        let length = UInt32(message.count)
        return Data((0..<4).map { UInt8(truncatingIfNeeded: length >> (8 * $0)) }) + message
    }
}

public enum PageHost {
    public struct Reply: Codable, Equatable {
        public var kept: Bool
        public var error: String?
        public var labels: [String]?
        public var wantDecks: [String]?

        public init(kept: Bool, error: String? = nil, labels: [String]? = nil, wantDecks: [String]? = nil) {
            self.kept = kept
            self.error = error
            self.labels = labels
            self.wantDecks = wantDecks
        }

        public var framed: Data { NativeMessage.frame((try? JSONEncoder().encode(self)) ?? Data()) }
    }

    private struct Envelope: Decodable {
        var type: String?
    }

    public static func answer(_ message: Data, store: Store, decks: DeckAssembly = DeckAssembly()) -> Reply {
        do {
            let decoder = JSONDecoder()
            switch try decoder.decode(Envelope.self, from: message).type {
            case nil:
                let page = try decoder.decode(WebPage.self, from: message)
                let batch = page.batch(policy: try store.currentPolicy(), at: store.clock())
                if let batch { try store.record(batch) }
                return Reply(kept: batch != nil)
            case "mail_status": return try MailIntake.status(store: store)
            case "mail": return try MailIntake.keep(try decoder.decode(MailMessage.self, from: message), store: store)
            case "mail_deck":
                return try MailIntake.keep(
                    try decoder.decode(DeckChunk.self, from: message), decks: decks, store: store)
            case let other?: return Reply(kept: false, error: "unknown message type \(other)")
            }
        } catch {
            return Reply(kept: false, error: "\(error)")
        }
    }

    public static func serve(read: (Int) -> Data, write: (Data) -> Void, store: Store) {
        let decks = DeckAssembly()
        while true {
            let header = read(4)
            guard header.count == 4 else { return }
            let length = header.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            guard length <= NativeMessage.maximumLength else {
                write(Reply(kept: false, error: "\(NativeMessage.Failure.tooLong(length))").framed)
                return
            }
            let message = read(length)
            guard message.count == length else {
                write(Reply(kept: false, error: "\(NativeMessage.Failure.truncated)").framed)
                return
            }
            write(answer(message, store: store, decks: decks).framed)
        }
    }

    public static func receive(_ input: Data, store: Store) -> Data {
        var rest = input
        var out = Data()
        serve(
            read: { count in
                let chunk = rest.prefix(count)
                rest = rest.dropFirst(chunk.count)
                return Data(chunk)
            }, write: { out += $0 }, store: store)
        return out
    }
}
