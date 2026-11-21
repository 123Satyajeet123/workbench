import Foundation
import GRDB
import Synchronization
import Testing

@testable import WorkbenchCore

@Suite struct ClaimStoreTests {
    private let line = Evidence(
        id: 3, start: t0, line: "Founder — Pitch — deck.pdf page 4: We raised $20 million in 2023.",
        quotable: ["We raised $20 million in 2023."])

    private func extracted(_ reply: String, store: Store) async throws -> (claims: [Claim], dropped: Int, run: RunID?) {
        try await ClaimExtractor(model: RecordedModel(ScriptedModel(reply), store: store))
            .extract(deal: "d1", lines: [line])
    }

    @Test func aClaimIsKeptOnlyWhenItCitesAGivenLineAndQuotesIt() async throws {
        let store = try makeStore()
        let good =
            #"{"line":3,"text":"Raised $20 million.","type":"funding","value":"$20 million","quote":"raised $20 million"}"#
        let wrongLine = good.replacingOccurrences(of: #""line":3"#, with: #""line":9"#)
        let wrongQuote = good.replacingOccurrences(of: "raised $20 million", with: "raised $30 million")
        let result = try await extracted(#"{"claims":[\#(good),\#(wrongLine),\#(wrongQuote)]}"#, store: store)
        #expect(result.claims.map(\.text) == ["Raised $20 million."] && result.dropped == 2)
        #expect(try store.queries.runText(of: try #require(result.run))?.kinds == [.mail])
    }

    @Test func claimsAndTheChoiceAreKeptPerDealAndRoundTrip() async throws {
        let store = try makeStore()
        let good =
            #"{"line":3,"text":"Raised $20 million.","type":"funding","value":"$20 million","quote":"raised $20 million"}"#
        let result = try await extracted(#"{"claims":[\#(good)]}"#, store: store)
        let ids = try store.saveClaims(
            result.claims, run: try #require(result.run), grant: grant(.mail, label: "Deals"))
        try store.choose(claims: ids, deal: "d1")
        let claims = try store.queries.claims(of: "d1")
        #expect(claims.map(\.id) == ids.map { Optional($0) } && claims[0].type == .funding && claims[0].line == 3)
        #expect(try store.queries.claims(of: "d2").isEmpty)
        #expect(try store.queries.chosenClaims(of: "d1") == ids)
    }

    @Test func savingClaimsNeedsTheMailGrant() async throws {
        let store = try makeStore()
        let result = try await extracted(#"{"claims":[]}"#, store: store)
        #expect(throws: StoreError.grantForOtherKind(granted: .web, requested: .mail)) {
            try store.saveClaims([], run: try #require(result.run), grant: grant(.web))
        }
    }

    private func savedCheck(store: Store, at date: Date = t0) async throws -> Int64 {
        try store.switchWeb(true)
        let session = try WebSession.fake(store: store, search: FakeSearch(), pages: FakePages())
        let model = RecordedModel(ScriptedModel("{}"), store: store)
        let (_, run) = try await model.generate(
            [String: JSONValue].self, schema: .object([]), task: "t", instructions: "i", input: "page text",
            holding: [.web, .mail])
        let check = ClaimCheck(
            claim: 7, deal: "d1", claimText: "Acme raised $20 million.", verdict: .contradicted,
            quote: "raised $11 Mn", url: "https://news.example/a", checkedAt: date)
        return try store.saveCheck(check, claimQuote: "raised $20 million", run: run, session: session)
    }

    @Test func aCheckIsKeptWithTwoMarksAndTheLatestCheckOfAClaimShows() async throws {
        let store = try makeStore()
        let id = try await savedCheck(store: store)
        var shown = try #require(try store.queries.claimChecks(of: "d1").first)
        #expect(
            shown.verdict == .contradicted && shown.quote == "raised $11 Mn" && shown.url == "https://news.example/a")
        #expect(shown.verdictMark == .proposed && shown.quoteMark == .proposed)
        try store.mark(item: id, as: .confirmed)
        try store.markQuote(of: id, as: .rejected)
        shown = try #require(try store.queries.claimChecks(of: "d1").first)
        #expect(shown.verdictMark == .confirmed && shown.quoteMark == .rejected)
        _ = try await savedCheck(store: store)
        #expect(try store.queries.claimChecks(of: "d1").count == 1, "one row per claim: the latest check")
    }

    @Test func aPrivacyDeleteOfTheWebKindRemovesChecksAndTheFetchedPageTextButNotTheClaims() async throws {
        let store = try makeStore()
        let good =
            #"{"line":3,"text":"Raised $20 million.","type":"funding","value":"$20 million","quote":"raised $20 million"}"#
        let result = try await extracted(#"{"claims":[\#(good)]}"#, store: store)
        try store.saveClaims(result.claims, run: try #require(result.run), grant: grant(.mail, label: "Deals"))
        _ = try await savedCheck(store: store)
        let runs = try store.queries.runs()
        let checkRun = try #require(runs.first { $0.task == "t" }).id
        try store.delete(.kind(.web, before: nil))
        #expect(try store.queries.claimChecks(of: "d1").isEmpty)
        #expect(try store.queries.runText(of: checkRun) == nil, "the page text is gone")
        #expect(try store.queries.claims(of: "d1").count == 1, "the deck claims are mail, not web")
    }

    @Test func theRetentionRemovesOldChecksAndTheirPageTextAndKeepsNewOnes() async throws {
        let now = Mutex(t0)
        let store = try makeStore(clock: { now.withLock { $0 } })
        _ = try await savedCheck(store: store)
        let oldRun = try #require(try store.queries.runs().first).id
        now.withLock { $0 = day(20) }
        _ = try await savedCheck(store: store)
        now.withLock { $0 = day(31) }
        try store.delete(.everything(before: day(31).addingTimeInterval(-30 * 86_400)))
        #expect(try store.queries.runText(of: oldRun) == nil)
        #expect(try store.queries.claimChecks(of: "d1").count == 1, "the 20-day-old check stays")
        now.withLock { $0 = day(60) }
        try store.delete(.everything(before: day(60).addingTimeInterval(-30 * 86_400)))
        #expect(try store.queries.claimChecks(of: "d1").isEmpty)
    }

    @Test func aStoreBeforeTheQuoteMarksStepKeepsItsRowsAndGainsTheTable() throws {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let before = Schema.steps.count - 1
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        try queue.write { db in
            for statement in Schema.steps.prefix(before).joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = \(before)")
            try db.execute(
                sql: "INSERT INTO state(key, value, saved_at) VALUES ('kept', 'yes', '2026-11-19T10:00:00Z')")
        }
        let store = try Store(directory: folder)
        #expect(try store.queries.state(forKey: "kept") == "yes")
        let tables = try queue.read {
            try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE name = 'quote_mark'")
        }
        #expect(tables == ["quote_mark"])
    }
}
