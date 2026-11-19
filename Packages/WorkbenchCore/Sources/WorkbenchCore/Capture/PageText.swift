import Foundation

/// The text of a web page as the person saw it, sent by the Workbench browser extension. Chromium browsers do not show
/// page text to a read-only Accessibility client (measured on Brave, 2026-11-19), so the extension reads it in the
/// page instead. A page is screen text from a browser: the same switch, private rules and deletion apply.
public struct WebPage: Codable, Sendable, Equatable {
    /// The browser's bundle id, such as com.brave.Browser.
    public var browser: String
    public var url: String
    public var title: String
    /// Only the text that was on screen.
    public var text: String

    public init(browser: String, url: String, title: String, text: String) {
        self.browser = browser
        self.url = url
        self.title = title
        self.text = text
    }

    /// The batch to keep, or nil when the policy keeps no text of this page.
    public func batch(policy: CapturePolicy, at now: Date) -> ActivityBatch? {
        guard policy.isEnabled(.screenText), CapturePolicy.browserBundleIDs.contains(browser), !text.isEmpty else {
            return nil
        }
        let snapshot = ScreenSnapshot(
            app: browserName, bundleID: browser, windowID: 0, document: url, title: title, text: text)
        guard case .keep(let grant) = policy.verdict(for: snapshot, at: now) else { return nil }
        return ActivityBatch(
            [
                Activity(
                    at: now, kind: .text, app: browserName, bundleID: browser, title: title,
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
    /// Characters of page text one reading sends at most (about 50k tokens).
    public static let budget = 200_000

    /// A site as typed ("https://www.site.example/feed", "Site.example") made a host to match: "site.example".
    public static func site(_ typed: String) -> String? {
        guard let host = CapturePolicy.host(of: typed.trimmingCharacters(in: .whitespacesAndNewlines)),
            host.contains(".")
        else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The page texts of a day a machine reads: only browser text on the named sites, a page's repeated text once,
    /// earliest first up to the budget. `leftOut` counts the pages past the budget.
    public static func reading(_ activities: [Activity], sites: [String], budget: Int = budget) -> (
        pages: [Activity], leftOut: Int
    ) {
        let named = Set(sites)
        var seen = Set<String>()
        var pages: [Activity] = []
        var used = 0
        var leftOut = 0
        for activity in activities.sorted(by: { $0.at < $1.at })
        where activity.kind == .text && CapturePolicy.browserBundleIDs.contains(activity.bundleID) {
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

/// Chrome's native messaging frame: a 4-byte length in native byte order (little-endian on Macs), then UTF-8 JSON.
public enum NativeMessage {
    /// Larger messages are refused: a page's visible text is far smaller.
    public static let maximumLength = 256 * 1024

    public enum Failure: Error, Equatable {
        case truncated
        case tooLong(Int)
    }

    /// The message at the start of `data`, and how many bytes it took; nil when `data` is empty.
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

/// The native host's work for one message: keep the page if the policy allows, and answer whether it was kept.
public enum PageHost {
    public struct Reply: Codable, Equatable {
        public var kept: Bool
        public var error: String?

        public init(kept: Bool, error: String? = nil) {
            self.kept = kept
            self.error = error
        }

        public var framed: Data { NativeMessage.frame((try? JSONEncoder().encode(self)) ?? Data()) }
    }

    /// Every message in `input`, each answered by one reply frame. A broken frame ends the input.
    public static func receive(_ input: Data, store: Store) -> Data {
        var rest = input
        var out = Data()
        while true {
            let reply: Reply
            do {
                guard let (message, used) = try NativeMessage.first(in: rest) else { break }
                rest = rest.dropFirst(used)
                let page = try JSONDecoder().decode(WebPage.self, from: message)
                let batch = page.batch(policy: try store.currentPolicy(), at: store.clock())
                if let batch { try store.record(batch) }
                reply = Reply(kept: batch != nil)
            } catch {
                out += Reply(kept: false, error: "\(error)").framed
                if error is NativeMessage.Failure { break }
                continue
            }
            out += reply.framed
        }
        return out
    }
}
