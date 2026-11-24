import CaptureService
import Foundation
import SwiftUI
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Answers with the reply whose key the article text holds, so each article reads differently.
final class ArticleModel: StructuredModel, Sendable {
    let name = "articles"
    let replies: [String: String]

    init(_ replies: [String: String]) { self.replies = replies }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        let reply = replies.first { input.contains($0.key) }?.value ?? #"{"items":[]}"#
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: "m", usage: Usage(), reply: reply)
    }
}

/// The Signals page, a deal card with a signal and a revisit on Today, drawn to PNGs for a person to look at. The
/// folder comes from `VC_PREVIEW_DIR`, else the temporary folder.
@MainActor
@Suite struct NewsRenderTests {
    private func item(_ title: String, link: String, body: String) -> String {
        """
        <item><title>\(title)</title><link>\(link)</link><pubDate>\(NewsFixture.rfc822(.now))</pubDate>
        <content:encoded><![CDATA[<p>\(body)</p>]]></content:encoded></item>
        """
    }

    private func feed(_ items: String) -> String {
        """
        <rss xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>\(items)</channel></rss>
        """
    }

    private func reply(_ company: String, _ event: String, _ polarity: String, cite: Int, quote: String) -> String {
        #"{"items":[{"company":"\#(company)","event":"\#(event)","polarity":"\#(polarity)","date":"","cite":\#(cite),"quote":"\#(quote)"}]}"#
    }

    /// A passed deal with a bad signal and a revisit due today, an invested deal with a good one, and the Signals
    /// machine over the same store.
    private func world() async throws -> (NewsFixture, HelperModel, WorkObject, TodayModel) {
        let layoff = "Bolt Pay laid off 40 percent of its staff on Friday."
        let round = "Orbit Labs raised 5 million dollars in a seed round led by Nexus."
        let world = try NewsFixture(feeds: [
            .inc42: feed(item("Bolt Pay lays off 40% of staff", link: "https://inc42.com/a/1", body: layoff)),
            .yourStory: feed(item("Orbit Labs raises 5 million", link: "https://yourstory.com/a/2", body: round)),
        ])
        try world.switchWeb(true)
        let bolt = try world.passed("Bolt Pay Pvt Ltd", revisit: WorkDay(containing: .now))
        let orbitID = try #require(world.fixture.deals.create(title: "Orbit Labs"))
        let orbit = try #require(world.fixture.deals.deal(orbitID))
        world.fixture.deals.move(orbit, to: dealStage("Invested"))
        let model = ArticleModel([
            "Bolt Pay laid off": reply("Bolt Pay Pvt Ltd", "layoff", "negative", cite: 1, quote: layoff),
            "Orbit Labs raised": reply("Orbit Labs", "funding", "positive", cite: 2, quote: round),
        ])
        let crew = Crew(
            store: world.store, capture: world.capture, founder: { "Aditya" }, notifier: FakeNotifier())
        let id = try #require(crew.create(from: .newsSignals, name: "Signals"))
        let helper = try #require(crew.helper(id: id))
        _ = try await world.news.check(with: RecordedModel(model, store: world.store), spec: helper.spec)
        world.fixture.deals.refresh()
        helper.reload()
        return (
            world, helper, try #require(world.fixture.deals.deal(bolt.id)), TodayModel(store: world.store, crew: crew)
        )
    }

    @Test func theSignalsPageShowsEachFollowedCompanyWithItsSignals() async throws {
        let (world, helper, _, _) = try await world()
        #expect(helper.isReady)
        #expect(helper.items.map { $0["company"] } == ["Bolt Pay Pvt Ltd", "Orbit Labs"])
        let catalog = TeamCatalogModel(
            store: world.store, crew: world.fixture.crew, author: { "Aditya" }, secrets: MemorySecrets())
        let page = HelperContent(model: helper)
            .environment(ActionsModel(store: world.store, founder: { "Aditya" })).environment(world.fixture.crew)
            .environment(catalog)
            .environment(world.fixture.deals).environment(try captureSettings(over: world.store))
        try renderPNG(page, named: "signals-page", width: 820)
    }

    @Test func aDealCardShowsItsLatestSignalAndItsRevisitDay() async throws {
        let (world, _, bolt, _) = try await world()
        let card = DealCard(deal: bolt, digest: world.fixture.deals.digests[bolt.id]).frame(width: 240)
            .environment(world.fixture.deals)
        try renderPNG(card, named: "deal-card-signal", width: 320)
        let detail = DealDetail(deal: bolt, move: { _, _ in }, close: {}).frame(width: 400)
            .environment(world.fixture.deals).environment(RunsModel(store: world.store))
            .environment(world.fixture.makeClaims())
        try renderPNG(detail.fixedSize(horizontal: false, vertical: true), named: "deal-detail-signal", width: 440)
    }

    @Test func aRevisitIsOnTodayWithTheNewsSinceThePassAndBadNewsBesideIt() async throws {
        let (_, _, _, today) = try await world()
        #expect(today.lines.map(\.reason) == [.revisit, .news])
        try renderPNG(TodayBody(model: today), named: "today-revisit", width: 760)
    }
}
