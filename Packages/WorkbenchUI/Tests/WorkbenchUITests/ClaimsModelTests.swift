import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

final class RepliesInOrder: StructuredModel, Sendable {
    let name = "in-order"
    private let replies: Mutex<[String]>
    let inputs = Mutex<[String]>([])

    init(_ replies: [String]) { self.replies = Mutex(replies) }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        inputs.withLock { $0.append(input) }
        let text = replies.withLock { $0.isEmpty ? "{}" : $0.removeFirst() }
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(text.utf8)), model: "in-order-1", usage: Usage(),
            reply: text)
    }
}

final class RecordingSearch: SearchProvider, PageFetching, Sendable {
    let queries = Mutex<[String]>([])
    let fetched = Mutex<[URL]>([])
    static let article = URL(string: "https://news.example/acme")!
    static let text = "Acme has raised $11 Mn in its seed funding round."

    func search(_ query: String, count: Int) async throws -> [SearchHit] {
        queries.withLock { $0.append(query) }
        return [SearchHit(title: "Acme", url: Self.article, snippet: "")]
    }

    func fetch(_ url: URL) async throws -> FetchedPage {
        fetched.withLock { $0.append(url) }
        return FetchedPage(url: url, text: Self.text)
    }
}

@MainActor
@Suite struct ClaimsModelTests {
    private let deckPart = MailPart(
        id: 11, threadID: "t1", messageID: "m1", kind: .deck, name: "deck.pdf", page: 2, label: "Deals",
        sender: "Priya", subject: "Acme pitch", sentAt: .now, seenAt: .now,
        text: "Acme raised $20 million in its seed round in 2023.")
    private static let extraction =
        #"{"claims":[{"line":11,"text":"Acme raised $20 million.","type":"funding","value":"$20 million","quote":"raised $20 million"}]}"#

    private struct Setup {
        var fixture: DealFixture
        var deal: WorkObject
        var claims: ClaimsModel
        var search: RecordingSearch
        var model: RepliesInOrder
    }

    private func setup(
        web: Bool = true, mail: Bool = true, key: String? = "k", cap: Int = 100,
        queries: String = #"["Acme seed round"]"#
    )
        async throws -> Setup
    {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme", reading: VCFixture.hot)
        try fixture.store.savePolicy(
            CapturePolicy(switches: [.web: web, .mail: mail], allowList: [.mail: ["Deals"]]))
        try fixture.store.saveWebSettings(WebSettings(provider: .brave, monthlyCap: cap))
        let search = RecordingSearch()
        let model = RepliesInOrder([
            Self.extraction, #"{"queries":\#(queries)}"#,
            #"{"verdict":"contradicted","page":1,"quote":"raised $11 Mn in its seed"}"#,
        ])
        let store = fixture.store
        let part = deckPart
        let claims = fixture.makeClaims(
            model: model,
            openSession: {
                try WebSession.open(store: store, key: { _ in key }, make: { _, _, _ in (search, search) })
            },
            deckParts: { _ in [part] })
        return Setup(fixture: fixture, deal: deal, claims: claims, search: search, model: model)
    }

    private func choseTheClaim(_ s: Setup) async throws {
        await s.claims.extract(from: s.deal)
        let claim = try #require(s.claims.state(of: s.deal).claims.first)
        s.claims.toggle(claim, in: s.deal)
    }

    @Test func claimsAreReadChosenCheckedAndShownWithTheirQuoteAndLink() async throws {
        let s = try await setup()
        try await choseTheClaim(s)
        #expect(
            s.claims.state(of: s.deal).claims.map(\.value) == ["$20 million"]
                && s.claims.state(of: s.deal).chosen.count == 1)
        await s.claims.checkChosen(in: s.deal)
        let check = try #require(s.claims.state(of: s.deal).checks.first)
        #expect(check.verdict == .contradicted && check.quote == "raised $11 Mn in its seed")
        #expect(check.url == RecordingSearch.article.absoluteString && s.claims.problems.text == nil)
        #expect(s.search.queries.withLock { $0 } == ["Acme seed round"])
    }

    @Test func withWebResearchOffNothingIsSentAndTheCheckSaysWhy() async throws {
        let s = try await setup(web: false)
        try await choseTheClaim(s)
        await s.claims.checkChosen(in: s.deal)
        #expect(s.search.queries.withLock { $0 }.isEmpty && s.search.fetched.withLock { $0 }.isEmpty)
        #expect(s.claims.problems.text?.contains("Web research is off") == true)
        #expect(s.claims.state(of: s.deal).checks.isEmpty)
        #expect(s.model.inputs.withLock { $0 }.count == 1, "only the deck reading ran, no check call")
    }

    @Test func withNoKeyNothingIsSentAndTheCheckSaysWhy() async throws {
        let s = try await setup(key: nil)
        try await choseTheClaim(s)
        await s.claims.checkChosen(in: s.deal)
        #expect(s.search.queries.withLock { $0 }.isEmpty)
        #expect(s.claims.problems.text?.contains("no search key") == true)
    }

    @Test func theCapStopsTheCheckBeforeTheQueryThatWouldPassIt() async throws {
        let s = try await setup(cap: 1, queries: #"["one","two"]"#)
        try await choseTheClaim(s)
        await s.claims.checkChosen(in: s.deal)
        #expect(s.search.queries.withLock { $0 } == ["one"])
        #expect(s.claims.problems.text?.contains("cap of 1") == true && s.claims.state(of: s.deal).checks.isEmpty)
    }

    @Test func withMailOffTheDeckIsNotRead() async throws {
        let s = try await setup(mail: false)
        await s.claims.extract(from: s.deal)
        #expect(s.claims.state(of: s.deal).claims.isEmpty && s.model.inputs.withLock { $0 }.isEmpty)
        #expect(s.claims.problems.text?.contains("Mail is switched off") == true)
    }

    @Test func theFounderMarksTheQuoteAndTheVerdictApart() async throws {
        let s = try await setup()
        try await choseTheClaim(s)
        await s.claims.checkChosen(in: s.deal)
        let check = try #require(s.claims.state(of: s.deal).checks.first)
        s.claims.markQuote(check, as: .confirmed, in: s.deal)
        s.claims.markVerdict(check, as: .rejected, in: s.deal)
        let marked = try #require(s.claims.state(of: s.deal).checks.first)
        #expect(marked.quoteMark == .confirmed && marked.verdictMark == .rejected)
    }

    @Test func settingsKeepTheKeyOutOfTheStoreAndTheConsentOffByDefault() throws {
        let store = try scratchStore()
        let secrets = MemorySecrets()
        let web = WebResearchSettings(store: store, secrets: secrets)
        #expect(try store.currentPolicy().isEnabled(.web) == false && !web.hasKey)
        web.provider = .exa
        web.monthlyCap = 50
        web.saveKey("  exa-secret ")
        #expect(web.hasKey && secrets.read("web-search-exa") == "exa-secret")
        #expect(try store.queries.state(forKey: "web.settings")?.contains("exa-secret") == false)
        let reopened = WebResearchSettings(store: store, secrets: secrets)
        #expect(reopened.provider == .exa && reopened.monthlyCap == 50 && reopened.hasKey)
        web.removeKey()
        #expect(!web.hasKey)
    }
}
