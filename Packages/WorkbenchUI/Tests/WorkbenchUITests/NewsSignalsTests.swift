import CaptureService
import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

extension NewsFeed {
    static let inc42 = MachineTemplate.newsSignals.spec.feeds![0]
    static let yourStory = MachineTemplate.newsSignals.spec.feeds![1]
}

/// A fetcher that records every address and serves RSS bodies by address.
final class RecordingFeeds: FeedFetching, Sendable {
    let fetched = Mutex<[URL]>([])
    let bodies: [URL: String]

    init(_ bodies: [NewsFeed: String]) {
        self.bodies = Dictionary(uniqueKeysWithValues: bodies.map { ($0.key.url, $0.value) })
    }

    func fetch(_ url: URL) async throws -> Data {
        fetched.withLock { $0.append(url) }
        return Data((bodies[url] ?? "<rss/>").utf8)
    }
}

/// The portfolio watch end to end over a scratch store: a passed deal, the news source behind the web consent, the
/// signals on the deal and on Today. No network and no model run: the fetcher and the model are scripts.
@MainActor
struct NewsFixture {
    static let quote = "Bolt Pay laid off 40 percent of its staff on Friday."
    static let reply =
        #"{"items":[{"company":"Bolt Pay","event":"layoff","polarity":"negative","date":"2026-09-19","cite":1,"quote":"\#(quote)"}]}"#

    static func rfc822(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return format.string(from: date)
    }

    let fixture: DealFixture
    let capture: CaptureService
    let feeds: RecordingFeeds
    let news: NewsSource
    let store: Store

    init(feeds bodies: [NewsFeed: String]? = nil) throws {
        fixture = try DealFixture()
        store = fixture.store
        capture = try CaptureService(store: store)
        feeds = RecordingFeeds(
            bodies ?? [
                .inc42: """
                <rss xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><item>
                <title>Bolt Pay lays off staff</title><link>https://inc42.com/a/1</link>
                <pubDate>\(Self.rfc822(.now))</pubDate>
                <content:encoded><![CDATA[<p>\(Self.quote) The fintech raised funds last year.</p>]]></content:encoded>
                </item></channel></rss>
                """
            ])
        let feeds = feeds
        news = NewsSource(store: store, capture: capture, makeFetcher: { _ in feeds })
    }

    func switchWeb(_ on: Bool) throws { try capture.update { $0.switches[.web] = on } }

    func check(reply: String = Self.reply) async throws -> NewsCheck.Report {
        try await news.check(
            with: RecordedModel(ScriptedModel(reply), store: store), spec: MachineTemplate.newsSignals.spec)
    }

    /// A deal passed on, with a revisit on `day`.
    func passed(_ title: String, revisit day: WorkDay?) throws -> WorkObject {
        let id = try #require(fixture.deals.create(title: title))
        fixture.deals.pass(try #require(fixture.deals.deal(id)), reason: "no revenue", revisit: day)
        return try #require(fixture.deals.deal(id))
    }
}

@MainActor
@Suite struct NewsSignalsTests {
    @Test func passingADealMovesItNotesWhyAndSetsTheRevisit() throws {
        let world = try NewsFixture()
        let due = WorkDay(containing: .now.addingTimeInterval(180 * 86_400))
        let bolt = try world.passed("Bolt Pay", revisit: due)
        #expect(bolt.stageLabels == ["Rejected"])
        #expect(bolt.notes.map(\.text) == ["Passed: no revenue"])
        let revisit = try #require(world.fixture.deals.digests[bolt.id]?.revisit)
        #expect(revisit.dueDay == due && revisit.quote == "Revisit Bolt Pay: passed for no revenue; anything new?")
    }

    @Test func passingWithNoRevisitSetsNoDatedFact() throws {
        let world = try NewsFixture()
        let bolt = try world.passed("Bolt Pay", revisit: nil)
        #expect(bolt.stageLabels == ["Rejected"] && world.fixture.deals.digests[bolt.id]?.revisit == nil)
        #expect(try world.store.queries.openRevisits().isEmpty)
    }

    @Test func aDealThatLeavesRejectedLosesItsRevisit() throws {
        let world = try NewsFixture()
        let bolt = try world.passed("Bolt Pay", revisit: WorkDay(containing: .now.addingTimeInterval(86_400 * 30)))
        world.fixture.deals.move(bolt, to: dealStage("Screen"))
        #expect(try world.store.queries.openRevisits().isEmpty)
    }

    @Test func withTheWebConsentOffTheMachineIsNotReadyAndACheckFetchesNothing() async throws {
        let world = try NewsFixture()
        _ = try world.passed("Bolt Pay", revisit: nil)
        #expect(!world.news.isReady)
        await #expect(throws: WebBlock.consentOff) { try await world.check() }
        #expect(world.feeds.fetched.withLock { $0 }.isEmpty, "nothing was sent")
        try world.switchWeb(true)
        #expect(world.news.isReady)
    }

    @Test func aCheckGivesAPassedDealItsSignalAndTheDealCardShowsIt() async throws {
        let world = try NewsFixture()
        try world.switchWeb(true)
        let bolt = try world.passed("Bolt Pay Private Limited", revisit: nil)
        let report = try await world.check(
            reply: NewsFixture.reply.replacingOccurrences(of: "\"Bolt Pay\"", with: "\"Bolt Pay Private Limited\""))
        #expect(report.kept == 1 && world.feeds.fetched.withLock { $0 }.map(\.host) == ["inc42.com", "yourstory.com"])
        world.fixture.deals.refresh()
        let signal = try #require(world.fixture.deals.digests[bolt.id]?.signals.first)
        #expect(signal["polarity"] == "negative" && signal.signalCompany == bolt.id)
    }

    @Test func theNewsMachineBoardNamesEveryFollowedCompanyEvenWithNoNews() async throws {
        let world = try NewsFixture()
        _ = try world.passed("Bolt Pay", revisit: nil)
        try world.news.add(name: "Orbit", aliases: "Orbit Labs, Orbital", domain: "https://www.orbit.example/x")
        try world.news.refresh(on: WorkDay(containing: .now))
        #expect(world.news.context[NewsSignals.companies] == ["Bolt Pay", "Orbit"])
        let orbit = try #require(world.news.companies.last)
        #expect(orbit.aliases == ["Orbit Labs", "Orbital"] && orbit.domain == "orbit.example")
        try world.news.setDetails(of: world.news.companies[0], aliases: "BoltX", domain: "bolt.example")
        #expect(world.news.companies[0].aliases == ["BoltX"] && world.news.companies[0].domain == "bolt.example")
        try world.news.remove(orbit)
        try world.news.remove(world.news.companies[0])
        #expect(world.news.companies.map(\.name) == ["Bolt Pay"], "a deal is followed by its stage, not removed here")
    }

    @Test func aRevisitIsOnTodayOnItsDayAndNotBeforeAndDoneClosesIt() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_790_000_000))
        let store = try scratchStore(clock: { clock.now })
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Aditya" }, notifier: FakeNotifier())
        let today = WorkDay(containing: clock.now)
        let deal = WorkObject.fold(
            [
                WorkEvent(object: "d1", author: "A", clock: 1, at: clock.now, kind: .create, text: "deal"),
                WorkEvent(object: "d1", author: "A", clock: 2, at: clock.now, kind: .title, text: "Bolt Pay"),
            ], viewer: "A")[0]
        try store.setRevisit(of: deal, on: today.adding(days: 3), reason: "no revenue")
        let model = TodayModel(store: store, crew: crew)
        #expect(model.lines.isEmpty, "before the day")
        clock.set(today.adding(days: 3).start.addingTimeInterval(8 * 3600))
        model.refresh()
        let need = try #require(model.lines.first)
        #expect(need.reason == .revisit && need.item.quote == "Revisit Bolt Pay: passed for no revenue; anything new?")
        model.perform(.done, on: [need.item], text: "Done")
        #expect(model.lines.isEmpty)
        #expect(try store.queries.revisits().first?.closed?.outcome == "done")
    }

    @Test func aRevisitShowsTheNewsSinceThePassAndBadNewsNeedsYouUntilDone() async throws {
        let world = try NewsFixture()
        try world.switchWeb(true)
        let bolt = try world.passed("Bolt Pay", revisit: WorkDay(containing: .now))
        _ = try await world.check()
        let model = TodayModel(store: world.store, crew: world.fixture.crew)
        let reasons = model.lines.map(\.reason)
        #expect(reasons == [.revisit, .news])
        let revisit = try #require(model.lines.first { $0.reason == .revisit }?.item)
        #expect(model.passedNews[try #require(revisit.id)]?.map(\.signalCompany) == [bolt.id])
        let bad = try #require(model.lines.first { $0.reason == .news }?.item)
        #expect(model.title(of: bad) == "Bolt Pay lays off staff")
        model.perform(.notRelevant, on: [bad], text: "Hidden")
        #expect(model.lines.map(\.reason) == [.revisit])
        #expect(try world.store.queries.newsSignals().count == 1, "it stays on the Signals page")
    }
}
