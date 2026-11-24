import Foundation
import GRDB
import Synchronization
import Testing

@testable import WorkbenchCore

/// The news check: consent first, then feed, match, one model call per matched article, and checks on each fact.
@Suite struct NewsCheckTests {
    private let layoff = "Bolt Pay laid off 40 percent of its staff on Friday."
    private let body = "Bolt Pay laid off 40 percent of its staff on Friday. The fintech raised funds last year."

    private func feeds() -> FakeFeeds {
        FakeFeeds([
            .inc42: rss(
                rssItem("Bolt Pay lays off staff", link: "https://inc42.com/a/1", body: body),
                rssItem("Weather today", link: "https://inc42.com/a/2", body: "Rain in Mumbai.")),
            .yourStory: rss(rssItem("Acme raises", link: "https://yourstory.com/a/3", body: "Acme raised $5M seed.")),
        ])
    }

    private func reply(
        company: String = "Bolt Pay", quote: String? = nil, date: String = "2026-09-19", cite: Int = 1
    ) -> String {
        #"{"items":[{"company":"\#(company)","event":"layoff","polarity":"negative","date":"\#(date)","cite":\#(cite),"quote":"\#(quote ?? layoff)"}]}"#
    }

    private func run(
        _ reply: String, watching: [WatchedCompany]? = nil, store: Store? = nil
    ) async throws -> (report: NewsCheck.Report, store: Store, model: ScriptedModel) {
        let store = try store ?? makeStore()
        try store.switchWeb(true)
        let model = ScriptedModel(reply)
        let check = NewsCheck(
            session: try .fake(store: store, feeds: feeds()), model: RecordedModel(model, store: store),
            spec: .news())
        let report = try await check.run(watching: watching ?? [company("Bolt Pay")])
        return (report, store, model)
    }

    @Test func withTheConsentOffNoFeedIsFetchedAndNoFetcherIsBuilt() throws {
        let store = try makeStore()
        var built = false
        #expect(throws: WebBlock.consentOff) {
            try FeedSession.open(
                store: store, feeds: [],
                make: { _ in
                    built = true
                    return FakeFeeds()
                })
        }
        #expect(!built)
        try store.switchWeb(false)
        #expect(throws: WebBlock.consentOff) { try FeedSession.fake(store: store, feeds: FakeFeeds()) }
        try store.savePolicy(CapturePolicy(mode: .off, switches: [.web: true]))
        #expect(throws: WebBlock.consentOff) { try FeedSession.fake(store: store, feeds: FakeFeeds()) }
    }

    @Test func aSessionOnlyFetchesTheFeedsItWasGivenAndStopsWhenItsGrantRunsOut() async throws {
        let now = Mutex(t0)
        let store = try makeStore(clock: { now.withLock { $0 } })
        try store.switchWeb(true)
        let fake = feeds()
        let session = try FeedSession.fake(store: store, feeds: fake)
        let stranger = NewsFeed(name: "Other", url: URL(string: "https://news.example/feed")!, trusted: true)
        await #expect(throws: FeedError.notAFeed(stranger.url)) { try await session.fetch(stranger) }
        now.withLock { $0 = t0.addingTimeInterval(CapturePolicy.grantLifetime + 1) }
        await #expect(throws: WebBlock.grantExpired) { try await session.fetch(.inc42) }
        #expect(fake.fetched.withLock { $0 }.isEmpty, "nothing was fetched")
    }

    @Test func aFeedParsesIntoEntriesWithFullTextAndAnAtomFeedToo() throws {
        let entries = try FeedParser.entries(
            in: Data(rss(rssItem("Bolt &amp; Co lays off", link: "https://inc42.com/a/1", body: body)).utf8))
        #expect(entries.count == 1 && entries[0].title == "Bolt & Co lays off")
        #expect(entries[0].text == body, "the full text of content:encoded, not the short description")
        #expect(entries[0].url.absoluteString == "https://inc42.com/a/1")
        let atom = """
            <feed xmlns="http://www.w3.org/2005/Atom"><title>F</title><entry><title>Acme raises</title>
            <link href="https://yourstory.com/a/9"/><updated>2026-09-20T08:00:00Z</updated>
            <summary>Acme raised a seed round.</summary></entry></feed>
            """
        let found = try FeedParser.entries(in: Data(atom.utf8))
        #expect(found.map(\.title) == ["Acme raises"] && found[0].text == "Acme raised a seed round.")
        #expect(throws: FeedError.unreadable) { try FeedParser.entries(in: Data("<rss><item>".utf8)) }
    }

    @Test func anEntryWithoutADateOrAnHttpsAddressIsLeftOut() throws {
        let xml = """
            <rss><channel><item><title>No date</title><link>https://inc42.com/x</link></item>
            <item><title>Plain http</title><link>http://inc42.com/y</link><pubDate>Mon, 21 Sep 2026 10:00:00 +0000</pubDate></item>
            </channel></rss>
            """
        #expect(try FeedParser.entries(in: Data(xml.utf8)).isEmpty)
    }

    @Test func oneModelCallReadsEachMatchedArticleAndTheFactIsTyped() async throws {
        let (report, store, model) = try await run(reply())
        #expect(report.newArticles == 3 && report.matched == 1 && report.kept == 1 && report.dropped == 0)
        #expect(model.inputs.withLock { $0 }.count == 1, "the weather and the Acme article named no followed company")
        let fact = try #require(try store.queries.newsSignals().first)
        #expect(fact["company"] == "Bolt Pay" && fact["event"] == "layoff" && fact["polarity"] == "negative")
        #expect(fact["date"] == "2026-09-19" && fact["feed"] == "Inc42" && fact["trusted"] == "yes")
        #expect(fact["url"] == "https://inc42.com/a/1" && fact.quote == layoff && fact.source == .web)
        #expect(fact.carriesAll(HelperSpec.Attention.builtIn.news))
        #expect(try store.queries.unreadArticles().map(\.title).sorted() == ["Acme raises", "Weather today"])
    }

    @Test func aQuoteThatIsNotInTheArticleIsDropped() async throws {
        let (report, store, _) = try await run(reply(quote: "Bolt Pay shut down all offices"))
        #expect(report.kept == 0 && report.dropped == 1)
        #expect(try store.queries.newsSignals().isEmpty)
    }

    @Test func aQuoteIsKeptAtTwentyFiveWordsAndDroppedAtTwentySix() async throws {
        func kept(words count: Int) async throws -> Int {
            let quote = (1...count).map { "w\($0)" }.joined(separator: " ")
            let store = try makeStore()
            try store.switchWeb(true)
            let feeds = FakeFeeds([
                .inc42: rss(rssItem("Bolt Pay long", link: "https://inc42.com/a/1", body: "Bolt Pay \(quote)."))
            ])
            let check = NewsCheck(
                session: try .fake(store: store, feeds: feeds),
                model: RecordedModel(ScriptedModel(reply(quote: quote)), store: store), spec: .news(feeds: [.inc42]))
            return try await check.run(watching: [company("Bolt Pay")]).kept
        }
        #expect(try await kept(words: 25) == 1)
        #expect(try await kept(words: 26) == 0)
    }

    @Test func aCompanyThatIsNotACandidateIsDropped() async throws {
        let (report, _, _) = try await run(reply(company: "Acme"))
        #expect(report.kept == 0 && report.dropped == 1)
    }

    @Test func aDateThatIsNotARealDayBecomesTheDayTheArticleCameOut() async throws {
        let (_, store, _) = try await run(reply(date: "last Friday"))
        let fact = try #require(try store.queries.newsSignals().first)
        #expect(fact["date"] == WorkDay(containing: t0.addingTimeInterval(-3600)).description)
    }

    @Test func twoCompaniesWithOneNameAreChosenBetweenByTheModelFromTheirLabels() async throws {
        let first = company("Bolt Pay", status: .portfolio)
        let second = company("Bolt Pay", status: .passed)
        let (_, store, model) = try await run(reply(company: "Bolt Pay (passed)"), watching: [first, second])
        let input = try #require(model.inputs.withLock { $0 }.first)
        #expect(input.contains("Companies: Bolt Pay (portfolio), Bolt Pay (passed)"))
        #expect(try store.queries.newsSignals(of: second.id).count == 1)
        #expect(try store.queries.newsSignals(of: first.id).isEmpty)
        let invented = try await run(reply(company: "Bolt Pay"), watching: [first, second])
        #expect(invented.report.kept == 0, "a name that is not one of the labels is not a candidate")
    }

    @Test func aRepeatedCheckFetchesAgainButReadsNothingTwice() async throws {
        let (_, store, _) = try await run(reply())
        let (second, _, model) = try await run(reply(), store: store)
        #expect(second.newArticles == 0 && second.matched == 0 && second.failedFeeds.isEmpty)
        #expect(model.inputs.withLock { $0 }.isEmpty)
        #expect(try store.queries.newsSignals().count == 1)
    }

    @Test func theNewsMachineFetchesOnlyTheFeedsInItsSpec() async throws {
        func fetched(listing feeds: [NewsFeed]) async throws -> [URL] {
            let store = try makeStore()
            try store.switchWeb(true)
            let fake = self.feeds()
            let check = NewsCheck(
                session: try .fake(store: store, feeds: fake, listing: feeds),
                model: RecordedModel(ScriptedModel("{}"), store: store), spec: .news(feeds: feeds))
            _ = try await check.run(watching: [])
            return fake.fetched.withLock { $0 }
        }
        #expect(try await fetched(listing: [.yourStory]) == [NewsFeed.yourStory.url])
        #expect(try await fetched(listing: [.inc42, .yourStory]) == [NewsFeed.inc42.url, NewsFeed.yourStory.url])
        #expect(try await fetched(listing: []).isEmpty)
    }

    @Test func aFeedAPersonAddsIsFetchedAndAFeedOnlyTheSessionListsIsNot() async throws {
        let store = try makeStore()
        try store.switchWeb(true)
        let own = HiringTemplate.jobFeed
        let fake = FakeFeeds([own: rss(rssItem("Hiring", link: "https://jobs.example/a/1", body: "Open role."))])
        let check = NewsCheck(
            session: try .fake(store: store, feeds: fake, listing: [own]),
            model: RecordedModel(ScriptedModel("{}"), store: store), spec: .news(feeds: [own, .inc42]))
        let report = try await check.run(watching: [])
        #expect(fake.fetched.withLock { $0 } == [own.url] && report.failedFeeds == ["Inc42"])
    }

    @Test func aFactIsTrustedOnlyWhenTheSpecListsItsFeedAsTrusted() async throws {
        func trusted(_ spec: HelperSpec) async throws -> String? {
            let result = try await SignalReader(
                model: RecordedModel(ScriptedModel(reply()), store: try makeStore()), spec: spec
            ).read(
                article("Bolt Pay lays off staff", text: layoff),
                candidates: [Candidate(company: company("Bolt Pay"), label: "Bolt Pay")])
            return result.items.first?.fields[NewsSignals.trustedField]
        }
        #expect(try await trusted(.news()) == "yes")
        #expect(try await trusted(.news(feeds: [])) == "no")
    }

    @Test func aFeedThatFailsIsNamedAndTheOthersAreStillChecked() async throws {
        let store = try makeStore()
        try store.switchWeb(true)
        let feeds = FakeFeeds([.yourStory: rss(rssItem("Acme raises", link: "https://yourstory.com/a/3", body: "Acme"))]
        )
        let check = NewsCheck(
            session: try .fake(store: store, feeds: feeds), model: RecordedModel(ScriptedModel("{}"), store: store),
            spec: .news())
        let report = try await check.run(watching: [])
        #expect(report.failedFeeds == ["Inc42"] && report.newArticles == 1)
    }

    @Test func aCompanyAddedLaterIsMatchedAgainstTheArticlesAlreadyKept() async throws {
        let (first, store, _) = try await run(reply(), watching: [])
        #expect(first.matched == 0)
        let (later, _, _) = try await run(reply(), store: store)
        #expect(later.matched == 1 && later.kept == 1)
    }

    @Test func aPrivacyDeleteOfTheWebKindRemovesTheArticlesAndTheirSignals() async throws {
        let (_, store, _) = try await run(reply())
        #expect(try store.queries.articleCount() == 3)
        try store.delete(.kind(.web, before: nil))
        #expect(try store.queries.articleCount() == 0)
        #expect(try store.queries.newsSignals().isEmpty)
    }

    @Test func articlesAreKeptThirtyDaysAndTheRetentionAndEveryFetchRemoveOlderOnes() async throws {
        let now = Mutex(t0)
        let store = try makeStore(clock: { now.withLock { $0 } })
        _ = try await run(reply(), store: store)
        now.withLock { $0 = day(29) }
        try store.delete(.everything(before: day(29).addingTimeInterval(-30 * 86_400)))
        #expect(try store.queries.articleCount() == 3, "29 days old: kept")
        now.withLock { $0 = day(31) }
        try store.delete(.everything(before: day(31).addingTimeInterval(-30 * 86_400)))
        #expect(try store.queries.articleCount() == 0, "31 days old: removed")
    }

    @Test func aFetchDropsArticlesPastTheRetentionAndNeverKeepsOldEntries() async throws {
        let now = Mutex(t0)
        let store = try makeStore(clock: { now.withLock { $0 } })
        _ = try await run(reply(), store: store)
        now.withLock { $0 = day(35) }
        let old = rss(rssItem("Ancient", link: "https://inc42.com/a/9", body: "x", at: day(2)))
        let session = try FeedSession.fake(store: store, feeds: FakeFeeds([.inc42: old]))
        let added = try store.saveArticles(try FeedParser.entries(in: Data(old.utf8)), feed: .inc42, session: session)
        #expect(added == 0, "published 33 days ago: not kept")
        #expect(try store.queries.articleCount() == 0, "the three of day 0 are past 30 days")
    }

    @Test func aStoreBeforeTheNewsStepKeepsItsRowsAndGainsTheTable() throws {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let before = 8  // the news step is the ninth
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        try queue.write { db in
            for statement in Schema.steps.prefix(before).joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = \(before)")
            try db.execute(
                sql: "INSERT INTO state(key, value, saved_at) VALUES ('kept', 'yes', '2026-11-19T10:00:00Z')")
        }
        let store = try Store(directory: folder)
        #expect(try store.queries.state(forKey: "kept") == "yes")
        #expect(try store.queries.articleCount() == 0)
    }
}
