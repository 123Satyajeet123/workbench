import Foundation

/// One check of the news: fetch the feeds, keep new articles, match each to the companies the investor follows, and
/// read each matched article with one model call. Nothing runs without a `FeedSession`, which exists only while the
/// web research consent is on.
public struct NewsCheck: Sendable {
    public struct Report: Sendable, Equatable {
        public var newArticles = 0
        public var matched = 0
        public var kept = 0
        public var dropped = 0
        /// Feeds that could not be fetched or read, by name. The other feeds were still checked.
        public var failedFeeds: [String] = []
    }

    public let session: FeedSession
    public let model: RecordedModel
    /// The machine's spec: its task owns the items, its brief is the model's instruction and its feeds are the
    /// only feeds fetched.
    public let spec: HelperSpec

    public init(session: FeedSession, model: RecordedModel, spec: HelperSpec) {
        self.session = session
        self.model = model
        self.spec = spec
    }

    public func run(watching watched: [WatchedCompany]) async throws -> Report {
        var report = Report()
        let store = session.store
        for feed in spec.feeds ?? [] {
            do {
                let entries = try FeedParser.entries(in: try await session.fetch(feed))
                report.newArticles += try store.saveArticles(entries, feed: feed, session: session)
            } catch let block as WebBlock {
                throw block
            } catch {
                report.failedFeeds.append(feed.name)
            }
        }
        let reader = SignalReader(model: model, spec: spec)
        for article in try store.queries.unreadArticles() {
            let candidates = EntityMatcher.candidates(in: article, among: watched)
            if !candidates.isEmpty {
                let result = try await reader.read(article, candidates: candidates)
                try store.saveReading(
                    result, of: spec, day: WorkDay(containing: article.published), scope: "",
                    grant: session.grant)
                report.matched += 1
                report.kept += result.items.count
                report.dropped += result.dropped
                try store.markRead(article: article.id)
            }
        }
        return report
    }
}
