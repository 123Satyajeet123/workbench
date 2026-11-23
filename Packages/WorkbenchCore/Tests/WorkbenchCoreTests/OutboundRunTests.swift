import Foundation
import Testing

@testable import WorkbenchCore

/// The outbound run: consent and the cap first, then search, fetch, one model call per page, and the checks on each
/// candidate. No network and no real model: the search, the fetcher and the model are scripts.
@Suite struct OutboundRunTests {
    private let roundup = "https://news.example/seed-roundup"
    private let text = "Acme (acme.com) raised a $2M seed round in March and has 40 paying customers. Bolt Pay raised."

    private var acme: String {
        candidateJSON(
            "Acme", domain: "acme.com", stageQuote: "raised a $2M seed round", traction: "yes",
            tractionQuote: "40 paying customers", quote: "Acme (acme.com) raised a $2M seed round")
    }

    private struct World {
        var record: OutboundRunRecord
        var store: Store
        var model: OutboundModel
        var search: FakeSearch
        var fetcher: FakePages
    }

    private func run(
        reply: String? = nil, store: Store? = nil, hits: [String]? = nil, pages: [String: String]? = nil,
        queries: String = OutboundModel.defaultQueries, cap: Int = 100
    ) async throws -> World {
        let store = try store ?? makeStore()
        try store.switchWeb(true)
        try store.saveWebSettings(WebSettings(provider: .brave, monthlyCap: cap))
        let search = FakeSearch(hits: (hits ?? [roundup]).map(hit))
        let fetcher = FakePages(pages ?? [roundup: text])
        let model = OutboundModel(queries: queries, pages: [roundup: reply ?? pageReply(acme)])
        let session = try WebSession.fake(store: store, search: search, pages: fetcher)
        let record = try await OutboundRun(session: session, model: RecordedModel(model, store: store)).run()
        return World(record: record, store: store, model: model, search: search, fetcher: fetcher)
    }

    @Test func withTheConsentOffOrNoKeyNothingIsSentAndNoModelRuns() throws {
        let store = try makeStore()
        let (search, model) = (FakeSearch(hits: [hit(roundup)]), OutboundModel())
        #expect(throws: WebBlock.consentOff) { try WebSession.fake(store: store, search: search, pages: FakePages()) }
        try store.switchWeb(true)
        try store.saveWebSettings(WebSettings(provider: .brave))
        #expect(throws: WebBlock.noKey) {
            try WebSession.fake(store: store, search: search, pages: FakePages(), key: nil)
        }
        #expect(search.queries.withLock { $0 }.isEmpty && model.inputs.withLock { $0 }.isEmpty)
        #expect(try store.queries.runs().isEmpty)
    }

    @Test func theMonthlyCapStopsTheSearchesAndThePagesAlreadyFoundAreStillRead() async throws {
        let world = try await run(cap: 2)
        #expect(world.search.queries.withLock { $0 }.count == 2, "the third query was never sent")
        #expect(world.record.stoppedByCap && world.record.cost.searches == 2)
        #expect(world.record.kept == 1)
        #expect(try world.store.queries.webQueriesSent(inMonthOf: t0) == 2)
        let full = try await run(cap: 3)
        #expect(!full.record.stoppedByCap && full.search.queries.withLock { $0 }.count == 3)
    }

    @Test func aRunWithTheCapAlreadyReachedFailsBeforeAnySearch() throws {
        let store = try makeStore()
        try store.switchWeb(true)
        try store.saveWebSettings(WebSettings(provider: .brave, monthlyCap: 0))
        #expect(throws: WebBlock.capReached(cap: 0)) {
            try WebSession.fake(store: store, search: FakeSearch(), pages: FakePages())
        }
    }

    @Test func aRuleQuoteFoundInThePageIsKeptAndOneNotInThePageReadsUnknown() async throws {
        let rules = try #require(HelperSpec.outbound.criteria)
        let kept = try await run().store.candidates()
        let right = try #require(kept.first)
        #expect(rules.results(from: right.fields).map(\.verdict) == [.pass, .pass])
        let invented = candidateJSON(
            "Acme", domain: "acme.com", stageQuote: "raised a $9M Series B round", traction: "yes",
            tractionQuote: "40 paying customers", quote: "Acme (acme.com) raised a $2M seed round")
        let wrong = try #require(try await run(reply: pageReply(invented)).store.candidates().first)
        let results = rules.results(from: wrong.fields)
        #expect(results.map(\.verdict) == [.unknown, .pass], "a quote that is not in the page is never a pass")
        #expect(results[0].quote?.isEmpty == true)
    }

    @Test func aCandidateWhoseQuoteOrNameIsNotInThePageIsDropped() async throws {
        let wrongQuote = candidateJSON("Acme", stageQuote: "raised a seed round", quote: "Acme raised $20M last week")
        let ghost = candidateJSON("Zenith", stageQuote: "raised a $2M seed round", quote: "raised a $2M seed round")
        let world = try await run(reply: pageReply(wrongQuote, ghost, acme))
        let kept = try world.store.candidates()
        #expect(kept.map { $0["company"] } == ["Acme"])
        #expect(try world.store.queries.runs().contains { $0.dropped == 2 })
    }

    @Test func aDomainThePageDoesNotWriteIsDropped() async throws {
        let invented = candidateJSON(
            "Acme", domain: "acme.io", stageQuote: "raised a $2M seed round", quote: "raised a $2M seed round")
        let kept = try await run(reply: pageReply(invented)).store.candidates()
        #expect(kept.first?["domain"] == "" && kept.first?[Outbound.urlField] == roundup)
    }

    @Test func aCandidateAlreadyInDealsOrRejectedIsLeftOutAndAFreshOneStays() async throws {
        let store = try makeStore()
        try store.addDeal("Acme Technologies Pvt Ltd", stage: "Inbox")
        try store.addDeal("Orbit Labs", stage: "Rejected")
        let page = "Acme raised a seed. Orbit raised a seed. Nova (nova.example) raised a seed. Pixel raised a seed."
        func entry(_ name: String, domain: String = "") -> String {
            candidateJSON(name, domain: domain, stageQuote: "raised a seed", quote: "raised a seed")
        }
        let reply = pageReply(entry("Acme"), entry("Orbit"), entry("Nova", domain: "nova.example"), entry("Pixel"))
        try store.saveState(
            try Coding.json([Rejection(company: "Nova Pay", domain: "nova.example", reason: "", at: t0)]),
            forKey: Store.rejectionsKey(Outbound.task))
        let world = try await run(reply: reply, store: store, pages: [roundup: page])
        #expect(try store.candidates().map { $0["company"] } == ["Pixel"])
        #expect(world.record.found == 4 && world.record.alreadyKnown == 3 && world.record.kept == 1)
        let again = try await run(reply: reply, store: store, pages: [roundup: page])
        #expect(again.record.kept == 0, "a candidate already listed is not added twice")
    }

    @Test func notAFitIsAWrongMarkThatKeepsTheReasonAndTheStartupStaysOut() async throws {
        let world = try await run()
        let item = try #require(try world.store.candidates().first)
        try world.store.rejectCandidate(item, reason: "too late stage")
        let marked = try #require(try world.store.candidates().first)
        #expect(marked.state == .rejected && marked.isHidden(at: t0))
        let reasons = try world.store.queries.rejections(task: Outbound.task)
        #expect(reasons.map(\.reason) == ["too late stage"] && reasons.first?.domain == "acme.com")
        let known = try world.store.queries.knownCompanies(task: Outbound.task)
        #expect(OutboundReview.list([marked], criteria: .starter, known: known, now: t0).isEmpty)
    }

    @Test func aCandidateThatBecomesADealLeavesTheListWithNoNewRun() async throws {
        let world = try await run()
        let item = try #require(try world.store.candidates().first)
        let before = OutboundReview.list(
            [item], criteria: .starter, known: try world.store.queries.knownCompanies(task: Outbound.task), now: t0)
        #expect(before.count == 1)
        try world.store.addDeal("Acme")
        let after = OutboundReview.list(
            [item], criteria: .starter, known: try world.store.queries.knownCompanies(task: Outbound.task), now: t0)
        #expect(after.isEmpty)
    }

    @Test func aSnoozedCandidateComesBackOnItsDay() async throws {
        let world = try await run()
        let item = try #require(try world.store.candidates().first)
        let later = WorkDay(containing: t0).adding(days: 3)
        try world.store.snoozeCandidate(item, until: later)
        let snoozed = try #require(try world.store.candidates().first)
        let known = try world.store.queries.knownCompanies(task: Outbound.task)
        #expect(OutboundReview.list([snoozed], criteria: .starter, known: known, now: t0).isEmpty)
        #expect(OutboundReview.list([snoozed], criteria: .starter, known: known, now: later.start).count == 1)
    }

    @Test func eachPageIsOneModelCallAndOnlyHttpsPagesAreFetched() async throws {
        let other = "https://blog.example/launch"
        let world = try await run(
            hits: [roundup, other, "http://plain.example/x"], pages: [roundup: text, other: "Nothing here."])
        #expect(world.model.pageCalls == 2)
        #expect(world.fetcher.fetched.withLock { $0 }.map(\.absoluteString) == [roundup, other])
        #expect(world.record.pagesRead == 2)
    }

    @Test func theRunKeepsItsQueriesAndAnEstimatedCostThatAddsSearchesAndModelCalls() async throws {
        let world = try await run()
        let record = try #require(try world.store.queries.outboundRuns(task: Outbound.task).first)
        #expect(record == world.record)
        #expect(record.queries.map(\.rule) == ["r_stage", "r_stage", "r_traction"])
        #expect(abs(record.cost.searchUSD - 0.015) < 1e-9, "three searches at 5 USD per 1,000")
        #expect(abs(record.cost.modelUSD - 0.02) < 1e-9, "the query call and one page call, 0.01 each")
        #expect(abs(OutboundCost.estimate(provider: .exa, searches: 10, pages: 5).totalUSD - 0.18) < 1e-9)
        let guess = OutboundCost.nextRun(criteria: .starter, provider: .brave, last: nil)
        #expect(guess.searches == 8 && guess.pages == 15 && abs(guess.totalUSD - 0.34) < 1e-9)
        let measured = OutboundCost.nextRun(criteria: .starter, provider: .brave, last: record.cost)
        #expect(
            abs(measured.modelUSD - 15 * record.cost.modelUSD / Double(record.cost.pages)) < 1e-9,
            "a measured page cost replaces the guess")
    }

    @Test func criteriaWithNoRuleToSearchRunNoModelAndSendNothing() async throws {
        var spec = HelperSpec.outbound
        spec.criteria = Criteria(rules: [
            Rule(role: .dealBreaker, test: .text(TextTest(says: "Sells weapons.", wants: false)))
        ])
        let store = try makeStore()
        try store.switchWeb(true)
        let (search, model) = (FakeSearch(hits: [hit(roundup)]), OutboundModel())
        let session = try WebSession.fake(store: store, search: search, pages: FakePages([roundup: text]))
        await #expect(throws: OutboundError.nothingToSearch) {
            try await OutboundRun(session: session, model: RecordedModel(model, store: store), spec: spec).run()
        }
        #expect(search.queries.withLock { $0 }.isEmpty && model.inputs.withLock { $0 }.isEmpty)
    }
}
