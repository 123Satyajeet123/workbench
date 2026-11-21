import Foundation
import GRDB

/// A news article kept for the portfolio watch: what a feed said, with the feed's name and when it was fetched.
public struct NewsArticle: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var feed: String
    public var url: URL
    public var title: String
    public var published: Date
    public var text: String

    public var isTrusted: Bool { NewsFeed.isTrusted(feed) }

    /// The words matching and the model read: the title and the text.
    var body: String { title + ". " + text }
}

extension Store {
    /// How long a fetched article is kept.
    public static let newsRetentionDays = 30

    /// Keeps the entries of one feed that are new and not older than the retention, then drops articles past it. The
    /// session proves the web consent was on when they were fetched. Returns how many entries were new.
    @discardableResult
    public func saveArticles(_ entries: [FeedEntry], feed: NewsFeed, session: FeedSession) throws -> Int {
        try check(session.grant, kind: .web)
        let now = clock()
        let oldest = now.addingTimeInterval(-Double(Self.newsRetentionDays) * 86_400)
        return try writer.write { db in
            var added = 0
            for entry in entries where entry.published >= oldest {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO news_article(feed, url, title, published_at, fetched_at, text)
                        VALUES (?,?,?,?,?,?)
                        """,
                    arguments: [
                        feed.name, entry.url.absoluteString, entry.title, entry.published.stored, now.stored,
                        entry.text,
                    ])
                added += db.changesCount
            }
            try db.execute(sql: "DELETE FROM news_article WHERE fetched_at < ?", arguments: [oldest.stored])
            return added
        }
    }

    /// Records that an article's signals were read. An article that names no followed company stays unread, so a
    /// company added later is matched against the last 30 days.
    public func markRead(article id: Int64) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE news_article SET read_at = ? WHERE id = ?", arguments: [clock().stored, id])
        }
    }
}

extension Queries {
    /// The articles whose signals nobody read yet, oldest first.
    public func unreadArticles() throws -> [NewsArticle] {
        try reader.read { db in
            try db.fetch(
                "news_article",
                """
                SELECT id, feed, url, title, published_at, text FROM news_article WHERE read_at IS NULL
                ORDER BY published_at, id
                """, as: NewsArticle.init(row:))
        }
    }

    public func articleCount() throws -> Int {
        try reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM news_article") ?? 0 }
    }
}

extension NewsArticle {
    init(row: Row) throws {
        guard let url = URL(string: try row.value("url") as String) else { throw StoredValueError("url") }
        self.init(
            id: try row.value("id"), feed: try row.value("feed"), url: url, title: try row.value("title"),
            published: try row.date("published_at"), text: try row.value("text"))
    }
}
