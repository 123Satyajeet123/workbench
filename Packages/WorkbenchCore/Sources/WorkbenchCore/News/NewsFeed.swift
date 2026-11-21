import Foundation

/// A news feed Workbench may fetch for the portfolio watch. Feeds are data: the two hosts below are the only feed
/// hosts the app names, and `FeedSession` refuses any other address.
public struct NewsFeed: Sendable, Equatable, Hashable {
    public var name: String
    public var url: URL
    /// A negative signal from a trusted feed goes to Today's "Needs you"; one from another feed stays on its page.
    public var trusted: Bool

    public init(name: String, url: URL, trusted: Bool) {
        self.name = name
        self.url = url
        self.trusted = trusted
    }

    public var host: String { url.host() ?? "" }

    public static let inc42 = NewsFeed(name: "Inc42", url: URL(string: "https://inc42.com/feed/")!, trusted: true)
    public static let yourStory = NewsFeed(
        name: "YourStory", url: URL(string: "https://yourstory.com/feed")!, trusted: true)
    public static let all = [inc42, yourStory]

    /// Whether a feed called `name` is trusted. An unknown name is not.
    public static func isTrusted(_ name: String) -> Bool { all.first { $0.name == name }?.trusted ?? false }
}

/// Fetches the bytes of a feed address. The one implementation sits in the web research package, behind the web grant.
public protocol FeedFetching: Sendable {
    func fetch(_ url: URL) async throws -> Data
}

public enum FeedError: Error, Equatable {
    case notAFeed(URL)
    case unreadable
}

/// The one door to the network for news feeds. A session exists only while the web research consent is on, and it
/// fetches only the addresses of the feeds it is given. It needs no key and counts against no search cap: a feed
/// fetch sends no query.
public struct FeedSession: Sendable {
    let grant: CaptureGrant
    let store: Store
    let fetcher: any FeedFetching
    let feeds: [NewsFeed]

    /// Opens a session when the consent is on. The fetcher is built only after that check passes, from the grant.
    public static func open(
        store: Store, feeds: [NewsFeed] = NewsFeed.all, make: (CaptureGrant) -> any FeedFetching
    ) throws -> FeedSession {
        guard let grant = try store.currentPolicy().authorize(CaptureRequest(kind: .web), at: store.clock()).grant
        else { throw WebBlock.consentOff }
        return FeedSession(grant: grant, store: store, fetcher: make(grant), feeds: feeds)
    }

    public func fetch(_ feed: NewsFeed) async throws -> Data {
        guard grant.kind == .web, grant.expiresAt > store.clock() else { throw WebBlock.grantExpired }
        guard feeds.contains(feed) else { throw FeedError.notAFeed(feed.url) }
        return try await fetcher.fetch(feed.url)
    }
}
