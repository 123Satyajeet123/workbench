import Foundation
@_exported import PagesRelay

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

    /// The batch to keep, or nil when the policy keeps no text of this page. Gmail and WhatsApp Web are never kept as
    /// pages: their text comes only as mail from the label the person named, and as chat lines from an allowed chat.
    public func batch(policy: CapturePolicy, at now: Date) -> ActivityBatch? {
        guard policy.isEnabled(.screenText), CapturePolicy.browserBundleIDs.contains(browser), !text.isEmpty,
            !CapturePolicy.isSite(url, in: [MailContext.site, WhatsAppWebSnapshot.host])
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

/// The app's work for one message the native host passed on: keep the page, mail or chat if the policy allows, and
/// answer whether it was kept.
public enum PageHost {
    public struct Reply: Codable, Equatable {
        public var kept: Bool
        public var error: String?
        /// The Gmail labels mail may be read in now; answers a "mail_status" message.
        public var labels: [String]?
        /// The attached files of a mail message whose decks the host still lacks.
        public var wantDecks: [String]?
        /// The WhatsApp chats the web page may be read for now; answers a "whatsapp_status" message.
        public var chats: [String]?
        /// Whether the app asks which chat is open now: the person has the chooser open.
        public var discover: Bool?

        public init(
            kept: Bool, error: String? = nil, labels: [String]? = nil, wantDecks: [String]? = nil,
            chats: [String]? = nil, discover: Bool? = nil
        ) {
            self.kept = kept
            self.error = error
            self.labels = labels
            self.wantDecks = wantDecks
            self.chats = chats
            self.discover = discover
        }

        public var framed: Data { NativeMessage.frame((try? JSONEncoder().encode(self)) ?? Data()) }
    }

    /// A message with no type is a page; mail messages name theirs.
    private struct Envelope: Decodable {
        var type: String?
    }

    /// Answers one message: keeps the page, mail or chat if the policy allows. `decks` holds the chunks of decks still
    /// arriving, so one value serves a whole session.
    public static func answer(
        _ message: Data, store: Store, decks: DeckAssembly = DeckAssembly(),
        whatsApp: WhatsAppWebIntake = .refusing
    ) -> Reply {
        do {
            let decoder = JSONDecoder()
            switch try decoder.decode(Envelope.self, from: message).type {
            case nil:
                let page = try decoder.decode(WebPage.self, from: message)
                let batch = page.batch(policy: try store.currentPolicy(), at: store.clock())
                if let batch { try store.record(batch) }
                return Reply(kept: batch != nil)
            case "whatsapp_status": return try whatsApp.status(store: store)
            case "whatsapp_chat_seen":
                return try whatsApp.see(decoder.decode(WhatsAppChatSeen.self, from: message), now: store.clock())
            case "whatsapp_web":
                return try whatsApp.keep(decoder.decode(WhatsAppWebSnapshot.self, from: message), store: store)
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

    /// Serves a browser: reads one frame, answers it at once, and repeats until the input ends. A browser keeps the
    /// pipe open until it has the answer, so the host must never wait for the end of the input before it answers.
    /// A broken or oversize frame is answered and ends the session.
    public static func serve(
        read: (Int) -> Data, write: (Data) -> Void, store: Store, whatsApp: WhatsAppWebIntake = .refusing
    ) {
        let decks = DeckAssembly()
        while true {
            switch NativeMessage.next(read: read) {
            case .end: return
            case .broken(let failure):
                write(Reply(kept: false, error: "\(failure)").framed)
                return
            case .message(let message):
                write(answer(message, store: store, decks: decks, whatsApp: whatsApp).framed)
            }
        }
    }

    /// Every message in `input`, each answered by one reply frame.
    public static func receive(_ input: Data, store: Store, whatsApp: WhatsAppWebIntake = .refusing) -> Data {
        var rest = input
        var out = Data()
        serve(
            read: { count in
                let chunk = rest.prefix(count)
                rest = rest.dropFirst(chunk.count)
                return Data(chunk)
            }, write: { out += $0 }, store: store, whatsApp: whatsApp)
        return out
    }
}
