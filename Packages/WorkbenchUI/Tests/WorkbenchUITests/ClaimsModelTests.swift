import Foundation
import Kernel
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Replies in order, remembering each input.
final class RepliesInOrder: StructuredModel, Sendable {
    let name = "in-order"
    private let replies: Mutex<[String]>
    let inputs = Mutex<[String]>([])

    init(_ replies: [String]) { self.replies = Mutex(replies) }

    func append(_ more: [String]) { replies.withLock { $0 += more } }

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
    private static let pitch = "Acme raised $20 million in its seed round in 2023."

    /// The pitch as the app reads it back: a line the host stored, with the label and authority the writer gave it.
    private static func storedPart(in store: Store) throws -> MailPart {
        let context = MailContext(
            browser: "com.brave.Browser", url: "https://mail.google.com/mail/u/0/#label/Deals/T1", label: "Deals",
            threadId: "T1", messageId: "m1")
        let mail = MailMessage(
            context: context, sender: "priya@acme.example", recipients: ["vc@fund.example"], text: pitch)
        try store.savePolicy(CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals"]]))
        _ = PageHost.answer(
            try JSONEncoder().encode(mail), store: store, browser: "com.brave.Browser",
            owner: .success(try PersonID("test-owner")))
        return try #require(try store.queries.mailParts(from: .distantPast, to: .distantFuture).first)
    }

    /// A part no store line stands behind: it has no label and no authority.
    private static let unlabelledPart = MailPart(
        id: 11, threadID: "t1", label: "Deals", sender: "priya@acme.example", sentAt: .now, text: pitch)

    private static func extraction(line: Int64) -> String {
        #"{"claims":[{"line":\#(line),"text":"Acme raised $20 million.","type":"funding","value":"$20 million","quote":"raised $20 million"}]}"#
    }

    private struct Setup {
        var fixture: DealFixture
        var deal: WorkObject
        var claims: ClaimsModel
        var search: RecordingSearch
        var model: RepliesInOrder
    }

    private func setup(
        web: Bool = true, mail: Bool = true, key: String? = "k", cap: Int = 100,
        queries: String = #"["Acme seed round"]"#, readsDeck: Bool = false, labelled: Bool = true
    )
        async throws -> Setup
    {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme", reading: VCFixture.hot)
        let part = labelled ? try Self.storedPart(in: fixture.store) : Self.unlabelledPart
        try fixture.store.savePolicy(
            CapturePolicy(switches: [.web: web, .mail: mail], allowList: [.mail: ["Deals"]]))
        try fixture.store.saveWebSettings(WebSettings(provider: .brave, monthlyCap: cap))
        let search = RecordingSearch()
        let model = RepliesInOrder(
            (readsDeck ? [Self.extraction(line: part.id ?? 0)] : []) + [
                #"{"queries":\#(queries)}"#,
                #"{"verdict":"contradicted","page":1,"quote":"raised $11 Mn in its seed"}"#,
            ])
        let store = fixture.store
        let claims = fixture.makeClaims(
            model: model,
            openSession: {
                try WebSession.open(store: store, key: { _ in key }, make: { _, _, _ in (search, search) })
            },
            deckParts: { _ in [part] })
        return Setup(fixture: fixture, deal: deal, claims: claims, search: search, model: model)
    }

    private static let knownLabel = Label(
        source: try! Source(owner: PersonID("me"), key: SourceKey("mail:deals")).id)

    /// A claim read from the deck, with the label code computed for it, kept as extraction keeps it.
    private func savedClaim(_ s: Setup, label: Label?, text: String = "Acme raised $20 million.") async throws {
        let store = s.fixture.store
        let (_, run) = try await RecordedModel(ScriptedModel("{}"), store: store).generate(
            [String: WorkbenchCore.JSONValue].self, schema: .object([]), task: ClaimExtractor.task, instructions: "i",
            input: "deck", holding: [.mail])
        let mailGrant = try #require(
            CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals"]])
                .authorize(CaptureRequest(kind: .mail, label: "Deals"), at: .now).grant)
        let claim = Claim(
            deal: s.deal.id, text: text, type: "funding", value: "$20 million",
            quote: "raised $20 million", line: 11, label: label)
        try store.saveClaims([claim], run: run, grant: mailGrant)
        s.claims.refresh(s.deal)
    }

    private func choseTheClaim(_ s: Setup, label: Label? = knownLabel) async throws {
        try await savedClaim(s, label: label)
        let claim = try #require(s.claims.state(of: s.deal).claims.first)
        s.claims.toggle(claim, in: s.deal)
    }

    @Test func anUnlabelledClaimInTheMiddleIsRefusedOnItsOwnAndTheLaterClaimsAreChecked() async throws {
        let s = try await setup()
        s.model.append(
            [#"{"queries":["Acme team"]}"#, #"{"verdict":"not_found","page":0,"quote":""}"#])
        try await savedClaim(s, label: Self.knownLabel, text: "First claim.")
        try await savedClaim(s, label: nil, text: "Middle claim.")
        try await savedClaim(s, label: Self.knownLabel, text: "Last claim.")
        for claim in s.claims.state(of: s.deal).claims { s.claims.toggle(claim, in: s.deal) }
        await s.claims.checkChosen(in: s.deal)
        let checked = s.claims.state(of: s.deal).checks.map(\.claimText)
        #expect(checked == ["First claim.", "Last claim."])
        #expect(s.search.queries.withLock { $0 } == ["Acme seed round", "Acme team"])
        #expect(s.claims.problems.text?.contains("Middle claim.") == true)
        #expect(s.claims.problems.text?.contains("First claim.") == false)
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
        #expect(s.model.inputs.withLock { $0 }.isEmpty, "no check call")
    }

    @Test func aClaimReadFromDeckLinesWithAKnownLabelHasThatLabelAndItsQueryLeaves() async throws {
        let s = try await setup(readsDeck: true)
        await s.claims.extract(from: s.deal)
        let claim = try #require(s.claims.state(of: s.deal).claims.first)
        let gmail = try SourceDescriptor.gmailMail.sourceID(owner: PersonID("test-owner"))
        #expect(claim.label == Label(source: gmail))
        s.claims.toggle(claim, in: s.deal)
        await s.claims.checkChosen(in: s.deal)
        #expect(s.search.queries.withLock { $0 } == ["Acme seed round"] && s.claims.problems.text == nil)
    }

    @Test func aClaimReadFromALineWithNoStoredLabelHasNoLabelSoItIsNotSearchedFor() async throws {
        let s = try await setup(readsDeck: true, labelled: false)
        await s.claims.extract(from: s.deal)
        let claim = try #require(s.claims.state(of: s.deal).claims.first)
        #expect(claim.label == nil)
        s.claims.toggle(claim, in: s.deal)
        await s.claims.checkChosen(in: s.deal)
        #expect(s.search.queries.withLock { $0 }.isEmpty && s.model.inputs.withLock { $0 }.count == 1)
        #expect(s.claims.problems.text?.contains("was not searched for") == true)
    }

    @Test func aClaimWithAKnownLabelIsSearchedForWhateverTheProvider() async throws {
        let s = try await setup()
        try await choseTheClaim(s)
        await s.claims.checkChosen(in: s.deal)
        #expect(s.search.queries.withLock { $0 } == ["Acme seed round"])
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

    @Test func withNoMachineListingClaimTypesNothingIsReadAndTheDeckSaysWhy() async throws {
        let s = try await setup()
        try s.fixture.store.setState(s.fixture.intake.machine, .deleted)
        await s.claims.extract(from: s.deal)
        #expect(s.claims.state(of: s.deal).claims.isEmpty && s.model.inputs.withLock { $0 }.isEmpty)
        #expect(s.claims.problems.text?.contains("No machine lists claim types") == true)
    }

    @Test func withMailOffTheDeckIsNotRead() async throws {
        let s = try await setup(mail: false, readsDeck: true)
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

    @Test func aNewPersonSearchesThroughTheModelWithNoKeyAndOnlyBraveAndExaAskForOne() throws {
        let store = try scratchStore()
        let web = WebResearchSettings(store: store, secrets: MemorySecrets())
        #expect(web.provider == .model && !web.needsKey && SearchProviderKind.allCases.contains(.model))
        try store.savePolicy(CapturePolicy(switches: [.web: true]))
        _ = try web.openSession()
        web.provider = .brave
        #expect(web.needsKey)
        #expect(throws: WebBlock.noKey) { try web.openSession() }
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
