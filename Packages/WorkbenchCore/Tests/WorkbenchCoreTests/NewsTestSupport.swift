import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

/// A feed fetcher that records every address and answers from a table of bodies. An address not in the table fails.
final class FakeFeeds: FeedFetching, Sendable {
    struct Down: Error {}

    let fetched = Mutex<[URL]>([])
    let bodies: [URL: String]

    init(_ bodies: [NewsFeed: String] = [:]) {
        self.bodies = Dictionary(uniqueKeysWithValues: bodies.map { ($0.key.url, $0.value) })
    }

    func fetch(_ url: URL) async throws -> Data {
        fetched.withLock { $0.append(url) }
        guard let body = bodies[url] else { throw Down() }
        return Data(body.utf8)
    }
}

extension NewsFeed {
    static let inc42 = MachineTemplate.newsSignals.spec.feeds![0]
    static let yourStory = MachineTemplate.newsSignals.spec.feeds![1]
}

extension HelperSpec {
    /// The news machine's spec, reading only `feeds`.
    static func news(feeds: [NewsFeed] = [.inc42, .yourStory]) -> HelperSpec {
        var spec = HelperSpec.newsSignals
        spec.feeds = feeds
        return spec
    }
}

extension FeedSession {
    static func fake(store: Store, feeds: FakeFeeds, listing: [NewsFeed] = [.inc42, .yourStory]) throws -> FeedSession {
        try open(store: store, feeds: listing, make: { _ in feeds })
    }
}

/// One RSS item, written the way WordPress feeds write it: a CDATA body in `content:encoded`.
func rssItem(_ title: String, link: String, body: String, at date: Date = t0.addingTimeInterval(-3600)) -> String {
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    return """
        <item><title>\(title)</title><link>\(link)</link><pubDate>\(format.string(from: date))</pubDate>
        <description>short</description><content:encoded><![CDATA[<p>\(body)</p>]]></content:encoded></item>
        """
}

func rss(_ items: String...) -> String {
    """
    <?xml version="1.0"?><rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
    <channel><title>Feed</title>\(items.joined())</channel></rss>
    """
}

/// A deal as the fold of its events gives it.
func deal(_ title: String, stage: String, id: String = UUID().uuidString) throws -> WorkObject {
    let events = [
        WorkEvent(object: id, author: "Asha", clock: 1, at: t0, kind: .create, text: "deal"),
        WorkEvent(object: id, author: "Asha", clock: 2, at: t0, kind: .title, text: title),
        WorkEvent(object: id, author: "Asha", clock: 3, at: t0, kind: .stage, text: stage),
    ]
    return try #require(WorkObject.fold(events, viewer: "Asha").first)
}

func article(
    _ title: String, text: String, id: Int64 = 1, feed: String = "Inc42", at date: Date = t0.addingTimeInterval(-3600)
) -> NewsArticle {
    NewsArticle(
        id: id, feed: feed, url: URL(string: "https://inc42.com/a/\(id)")!, title: title, published: date, text: text)
}

func company(
    _ name: String, aliases: [String] = [], domain: String? = nil, status: WatchedCompany.Status = .portfolio
) -> WatchedCompany {
    WatchedCompany(
        id: UUID().uuidString, name: name, aliases: aliases, domain: domain, status: status, isDeal: false)
}
