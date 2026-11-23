import Foundation
@_exported import PagesRelay

/// The text of a web page as the person saw it, sent by the Workbench browser extension. Chromium browsers do not show
/// page text to a read-only Accessibility client (measured on Brave, 2026-11-19), so the extension reads it in the
/// page instead. A page is screen text from a browser: the same switch, private rules and deletion apply.
public struct WebPage: Codable, Sendable, Equatable {
    /// The browser's bundle id, such as com.brave.Browser. The app sets it from the process that sent the message,
    /// never from the message.
    public var browser = ""
    public var url: String
    public var title: String
    /// Only the text that was on screen.
    public var text: String
    /// The address of the frame that gave this text, when it is not the page itself.
    public var frame: String?
    /// The lines of the page. Each carries the site's own id when a source gave one.
    public var items: [Item]?
    /// The place the items' ids belong to (a channel, a thread).
    public var container: Container?

    /// One line the extension read.
    public struct Item: Codable, Sendable, Equatable {
        /// The site's own id, or nil when no source gave one.
        public var id: String?
        /// Where the id came from (an attribute name or "url").
        public var via: String?
        public var text: String

        public init(id: String?, via: String?, text: String) {
            self.id = id
            self.via = via
            self.text = text
        }
    }

    public struct Container: Codable, Sendable, Equatable {
        public var value: String
        public var via: String

        public init(value: String, via: String) {
            self.value = value
            self.via = via
        }
    }

    private enum CodingKeys: String, CodingKey { case url, title, text, frame, items, container }

    public init(
        browser: String, url: String, title: String, text: String, frame: String? = nil, items: [Item]? = nil,
        container: Container? = nil
    ) {
        self.browser = browser
        self.url = url
        self.title = title
        self.text = text
        self.frame = frame
        self.items = items
        self.container = container
    }

    /// WhatsApp Web text never reaches the store through page capture.
    static let whatsAppWebHost = "web.whatsapp.com"

    /// The batch to keep, or nil when the policy keeps no text of this page. Gmail and WhatsApp Web are never kept as
    /// pages: Gmail text comes only as mail from the label the person named. A frame's text is kept only when the
    /// frame's own address passes the same rules as the page's.
    public func batch(policy: CapturePolicy, at now: Date) -> ActivityBatch? {
        let addresses = [url] + (frame.map { [$0] } ?? [])
        guard policy.isEnabled(.screenText), CapturePolicy.browserBundleIDs.contains(browser), !text.isEmpty,
            !addresses.contains(where: { CapturePolicy.isSite($0, in: [MailContext.site, Self.whatsAppWebHost]) })
        else { return nil }
        let grants = addresses.compactMap { keepGrant(for: $0, policy: policy, at: now) }
        guard grants.count == addresses.count, let grant = grants.first else { return nil }
        return ActivityBatch(
            [
                Activity(
                    at: now, kind: .page, app: browserName, bundleID: browser, title: title,
                    document: CaptureEngine.address(url), text: text)
            ], grant: grant)
    }

    private func keepGrant(for address: String, policy: CapturePolicy, at now: Date) -> CaptureGrant? {
        let snapshot = ScreenSnapshot(
            app: browserName, bundleID: browser, windowID: 0, document: address, title: title, text: text)
        guard case .keep(let grant) = policy.verdict(for: snapshot, at: now) else { return nil }
        return grant
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

    /// The page texts of a day a machine reads: only the extension's pages on the named sites, a repeated text once,
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

/// The app's work for one message the native host passed on: keep the page or mail if the policy allows, and
/// answer whether it was kept.
public enum PageHost {
    public struct Reply: Codable, Equatable {
        /// The id of the message this answers; the extension matches replies to messages by it.
        public var id: Int?
        public var kept: Bool
        public var error: String?
        /// The Gmail labels mail may be read in now; answers a "mail_status" message.
        public var labels: [String]?
        /// The attached files of a mail message whose decks the host still lacks.
        public var wantDecks: [String]?

        public init(
            id: Int? = nil, kept: Bool, error: String? = nil, labels: [String]? = nil, wantDecks: [String]? = nil
        ) {
            self.id = id
            self.kept = kept
            self.error = error
            self.labels = labels
            self.wantDecks = wantDecks
        }

        public var framed: Data { NativeMessage.frame((try? JSONEncoder().encode(self)) ?? Data()) }
    }

    /// A message with no type is a page; mail messages name theirs.
    private struct Envelope: Decodable {
        var type: String?
        var id: Int?
    }

    /// What the reply says when the browser behind the connection is not known: no page or mail is kept.
    public static let unknownBrowser = "the browser of this connection is not known"

    /// Answers one message: keeps the page or mail if the policy allows. `browser` is the bundle id the app found from
    /// the connection's process tree; nil keeps nothing. `decks` holds the chunks of decks still arriving, so one value
    /// serves a whole session.
    public static func answer(
        _ message: Data, store: Store, browser: String?, decks: DeckAssembly = DeckAssembly()
    ) -> Reply {
        var reply = keep(message, store: store, browser: browser, decks: decks)
        reply.id = (try? JSONDecoder().decode(Envelope.self, from: message))?.id
        return reply
    }

    private static func keep(_ message: Data, store: Store, browser: String?, decks: DeckAssembly) -> Reply {
        do {
            let decoder = JSONDecoder()
            switch try decoder.decode(Envelope.self, from: message).type {
            case nil:
                guard let browser else { return Reply(kept: false, error: unknownBrowser) }
                var page = try decoder.decode(WebPage.self, from: message)
                page.browser = browser
                let batch = page.batch(policy: try store.currentPolicy(), at: store.clock())
                if let batch { try store.record(batch) }
                return Reply(kept: batch != nil)
            case "adapter_state":
                return try AdapterState.keep(try decoder.decode(AdapterState.Report.self, from: message), store: store)
            case "mail_status": return try MailIntake.status(store: store)
            case "mail":
                guard let browser else { return Reply(kept: false, error: unknownBrowser) }
                var mail = try decoder.decode(MailMessage.self, from: message)
                mail.context.browser = browser
                return try MailIntake.keep(mail, store: store)
            case "mail_deck":
                guard let browser else { return Reply(kept: false, error: unknownBrowser) }
                var chunk = try decoder.decode(DeckChunk.self, from: message)
                chunk.context.browser = browser
                return try MailIntake.keep(chunk, decks: decks, store: store)
            case let other?: return Reply(kept: false, error: "unknown message type \(other)")
            }
        } catch {
            return Reply(kept: false, error: "\(error)")
        }
    }

    /// Serves a browser: reads one frame, answers it at once, and repeats until the input ends. A browser keeps the
    /// pipe open until it has the answer, so the host must never wait for the end of the input before it answers.
    /// A broken or oversize frame is answered and ends the session. A command result from the browser goes to
    /// `commands` and gets no reply.
    public static func serve(
        read: (Int) -> Data, write: (Data) -> Void, store: Store, browser: String?, commands: BrowserLink? = nil
    ) {
        let decks = DeckAssembly()
        while true {
            switch NativeMessage.next(read: read) {
            case .end: return
            case .broken(let failure):
                write(Reply(kept: false, error: "\(failure)").framed)
                return
            case .message(let message):
                if commands?.take(message) == true { continue }
                write(answer(message, store: store, browser: browser, decks: decks).framed)
            }
        }
    }

    /// Every message in `input`, each answered by one reply frame.
    public static func receive(_ input: Data, store: Store, browser: String?) -> Data {
        var rest = input
        var out = Data()
        serve(
            read: { count in
                let chunk = rest.prefix(count)
                rest = rest.dropFirst(chunk.count)
                return Data(chunk)
            }, write: { out += $0 }, store: store, browser: browser)
        return out
    }
}
