import Foundation
import Kernel
import Testing

@testable import WorkbenchCore

@Suite struct ClaimCheckTests {
    private let article = "https://news.example/acme"
    private let pageText = "Acme has raised $11 Mn in its seed funding round, led by Blume. It was founded in 2022."
    private static let knownLabel = Label(source: try! Source(owner: PersonID("me"), key: SourceKey("mail:deals")).id)
    private let claim = Claim(
        id: 7, deal: "deal-1", text: "Acme raised $20 million.", type: "funding", value: "$20 million",
        quote: "raised $20 million", line: 3, label: knownLabel)

    private func hits() -> FakeSearch {
        FakeSearch(hits: [SearchHit(title: "Acme", url: URL(string: article)!, snippet: "")])
    }

    private func check(verdict: String, page: Int = 1, quote: String, pages: [String: String]? = nil) async throws
        -> (result: ClaimCheck, search: FakeSearch, model: SequencedModel)
    {
        let store = try makeStore()
        try store.switchWeb(true)
        let search = hits()
        let session = try WebSession.fake(store: store, search: search, pages: FakePages(pages ?? [article: pageText]))
        let model = SequencedModel([
            #"{"queries":["Acme seed round","Acme funding"]}"#,
            #"{"verdict":"\#(verdict)","page":\#(page),"quote":"\#(quote)"}"#,
        ])
        let checker = ClaimChecker(model: RecordedModel(model, store: store), session: session, types: fundClaimTypes)
        return (try await checker.check(claim, company: "Acme").check, search, model)
    }

    @Test func aQuoteFoundInThePageKeepsTheVerdictWithItsAddress() async throws {
        let (result, search, _) = try await check(verdict: "contradicted", quote: "raised $11 Mn in its seed")
        #expect(result.verdict == .contradicted && result.quote == "raised $11 Mn in its seed")
        #expect(result.url == article)
        #expect(search.queries.withLock { $0 } == ["Acme seed round", "Acme funding"])
    }

    @Test func aQuoteNotInThePageMakesTheVerdictUnclear() async throws {
        for verdict in ["supported", "contradicted"] {
            let (result, _, _) = try await check(verdict: verdict, quote: "raised $20 million in a seed round")
            #expect(result.verdict == .unclear && result.quote.isEmpty && result.url.isEmpty, "\(verdict)")
        }
    }

    @Test func aVerdictThatNamesNoPageOrAnEmptyQuoteIsUnclear() async throws {
        let (noPage, _, _) = try await check(verdict: "supported", page: 0, quote: "seed funding round")
        let (noQuote, _, _) = try await check(verdict: "contradicted", quote: "")
        let (farPage, _, _) = try await check(verdict: "supported", page: 9, quote: "seed funding round")
        #expect([noPage, noQuote, farPage].allSatisfy { $0.verdict == .unclear })
    }

    @Test func notFoundIsNeverContradictedAndKeepsNoQuote() async throws {
        let (result, _, _) = try await check(verdict: "not_found", quote: "raised $11 Mn")
        #expect(result.verdict == .notFound && result.quote.isEmpty && result.url.isEmpty)
    }

    @Test func noPageFetchedMeansNoPublicEvidenceAndNoJudgeCall() async throws {
        let (result, _, model) = try await check(verdict: "contradicted", quote: "x", pages: [article: ""])
        #expect(result.verdict == .notFound)
        #expect(model.inputs.withLock { $0 }.count == 1, "only the query call ran")
    }

    @Test func aClaimOfATypeFromTheSpecIsCheckedWithWhatCountsAsProofForThatType() async throws {
        let store = try makeStore()
        try store.switchWeb(true)
        let session = try WebSession.fake(store: store, search: hits(), pages: FakePages([article: pageText]))
        let model = SequencedModel([#"{"queries":["q"]}"#, #"{"verdict":"not_found","page":0,"quote":""}"#])
        var licence = claim
        licence.type = "licence"
        let types = [ClaimType(id: "licence", label: "operating licence", proof: "The regulator's own register.")]
        _ = try await ClaimChecker(model: RecordedModel(model, store: store), session: session, types: types)
            .check(licence, company: "Acme")
        let inputs = model.inputs.withLock { $0 }
        #expect(inputs[1].contains("operating licence") && inputs[1].contains("The regulator's own register."))
        #expect(!inputs[0].contains("operating licence"), "the query writer does not see the type")
    }

    @Test func aClaimWhoseTypeTheSpecNoLongerListsIsStillChecked() async throws {
        let store = try makeStore()
        try store.switchWeb(true)
        let session = try WebSession.fake(store: store, search: hits(), pages: FakePages([article: pageText]))
        let model = SequencedModel([#"{"queries":["q"]}"#, #"{"verdict":"not_found","page":0,"quote":""}"#])
        let (result, _) = try await ClaimChecker(model: RecordedModel(model, store: store), session: session, types: [])
            .check(claim, company: "Acme")
        #expect(result.verdict == .notFound && model.inputs.withLock { $0 }[1].contains("funding"))
    }

    @Test func theJudgeReadsTheClaimAndThePageTextAndTheRunHoldsWebAndMail() async throws {
        let store = try makeStore()
        try store.switchWeb(true)
        let session = try WebSession.fake(store: store, search: hits(), pages: FakePages([article: pageText]))
        let model = SequencedModel([#"{"queries":["q"]}"#, #"{"verdict":"not_found","page":0,"quote":""}"#])
        let (_, run) = try await ClaimChecker(
            model: RecordedModel(model, store: store), session: session, types: fundClaimTypes
        )
        .check(claim, company: "Acme")
        let input = model.inputs.withLock { $0 }[1]
        #expect(input.contains("Acme raised $20 million.") && input.contains(pageText) && input.contains(article))
        #expect(try store.queries.runText(of: run)?.kinds == [.mail, .web])
    }

    @Test func withTheConsentOffTheCheckFailsBeforeAnyModelOrNetworkCall() throws {
        let store = try makeStore()
        let search = hits()
        #expect(throws: WebBlock.consentOff) { try WebSession.fake(store: store, search: search, pages: FakePages()) }
        let runs = try store.queries.runs()
        #expect(search.queries.withLock { $0 }.isEmpty && runs.isEmpty)
    }

    @Test func aFetchedPageThatIsNotHttpsIsNotRead() async throws {
        let store = try makeStore()
        try store.switchWeb(true)
        let plain = FakeSearch(hits: [SearchHit(title: "", url: URL(string: "http://news.example/a")!, snippet: "")])
        let pages = FakePages()
        let session = try WebSession.fake(store: store, search: plain, pages: pages)
        let model = SequencedModel([#"{"queries":["q"]}"#])
        let (result, _) = try await ClaimChecker(
            model: RecordedModel(model, store: store), session: session, types: fundClaimTypes
        )
        .check(claim, company: "Acme")
        #expect(pages.fetched.withLock { $0 }.isEmpty && result.verdict == .notFound)
    }

    @Test(arguments: [SearchProviderKind.model, .brave, .exa])
    func aClaimWithAKnownLabelIsSearchedForAndOneWithNoLabelNeverLeaves(provider: SearchProviderKind) async throws {
        let store = try makeStore()
        try store.switchWeb(true)
        try store.saveWebSettings(WebSettings(provider: provider))
        let search = hits()
        let session = try WebSession.fake(store: store, search: search, pages: FakePages([article: pageText]))
        let model = SequencedModel([
            #"{"queries":["Acme seed round"]}"#, #"{"verdict":"not_found","page":0,"quote":""}"#,
        ])
        let checker = ClaimChecker(model: RecordedModel(model, store: store), session: session, types: fundClaimTypes)

        _ = try await checker.check(claim, company: "Acme")
        #expect(search.queries.withLock { $0 } == ["Acme seed round"])

        var unlabelled = claim
        unlabelled.label = nil
        await #expect(throws: WebBlock.labelUnknown) { try await checker.check(unlabelled, company: "Acme") }
        #expect(search.queries.withLock { $0 }.count == 1, "no second query left")
        #expect(model.inputs.withLock { $0 }.count == 2, "no query writer call for the unlabelled claim")
    }

    @Test func aClaimKeepsItsLabelThroughTheStore() throws {
        let store = try makeStore()
        let run = try store.beginRun(task: Claim.task, model: "m", prompt: "p", input: "deck", kinds: [.mail])
        let ids = try store.saveClaims(
            [claim, Claim(deal: "deal-1", text: "No label.", type: "other", value: "x", quote: "q", line: 4)], run: run,
            grant: grant(.mail, label: "Deals"))
        let kept = try store.queries.claims(of: "deal-1")
        #expect(kept.map(\.label) == [Self.knownLabel, nil] && kept.count == ids.count)
    }

    @Test func theQueryWriterSeesOnlyTheCompanyNameAndTheClaimText() async throws {
        let store = try makeStore()
        try store.switchWeb(true)
        let session = try WebSession.fake(store: store, search: hits(), pages: FakePages())
        let model = SequencedModel([#"{"queries":["q"]}"#])
        var deckClaim = claim
        deckClaim.text = "Acme raised money."
        deckClaim.quote = "a quote only the deck holds"
        _ = try await ClaimChecker(model: RecordedModel(model, store: store), session: session, types: fundClaimTypes)
            .check(deckClaim, company: "Acme")
        let input = try #require(model.inputs.withLock { $0 }.first)
        #expect(input == "Company: Acme\nClaim: Acme raised money.")
        #expect(!input.contains(deckClaim.quote) && !input.contains(deckClaim.value))
    }

    @Test func htmlBecomesVisibleText() {
        let html =
            "<html><style>p{}</style><script>var x=1</script><p>Raised&nbsp;&#36;11 Mn</p><!-- c --><b>seed</b></html>"
        #expect(HTMLText.plain(html) == "Raised $11 Mn seed")
    }
}
