import Foundation
import Testing

@testable import WorkbenchCore

/// Ranking, the queries the model writes, and the offline eval.
@Suite struct OutboundReviewTests {
    private let criteria = Criteria(
        rules: [
            Rule(id: "r_stage", role: .must, test: .text(TextTest(says: "Raises a seed round.", wants: true))),
            Rule(id: "r_a", role: .plus, test: .text(TextTest(says: "Has revenue.", wants: true))),
            Rule(id: "r_b", role: .plus, test: .text(TextTest(says: "Has a repeat founder.", wants: true))),
        ], hotAt: 1)

    private func candidate(_ company: String, stage: String, a: String, b: String) -> Item {
        var fields = ["company": company]
        for (id, answer) in [("r_stage", stage), ("r_a", a), ("r_b", b)] {
            fields[id] = answer
            fields[id + "_quote"] = "words"
        }
        return Item(
            task: Outbound.task, day: WorkDay(containing: t0), scope: "", source: .web, citeFirst: 1, citeLast: 1,
            start: t0, end: t0, fields: fields, quote: "words", run: nil)
    }

    @Test func candidatesAreRankedByClassThenPointsThenName() {
        let found = [
            candidate("Delta", stage: "no", a: "yes", b: "yes"),
            candidate("Cyan", stage: "yes", a: "no", b: "no"),
            candidate("Bravo", stage: "yes", a: "yes", b: "no"),
            candidate("Alpha", stage: "yes", a: "yes", b: "yes"),
            candidate("Acorn", stage: "yes", a: "yes", b: "no"),
        ]
        let ranked = OutboundReview.rank(found, criteria: criteria)
        #expect(ranked.map(\.company) == ["Alpha", "Acorn", "Bravo", "Cyan", "Delta"])
        #expect(ranked.map(\.triage.rating) == [.hot, .hot, .hot, .warm, .cold])
        #expect(ranked.map(\.triage.points) == [2, 1, 1, 0, 2], "a deal-breaker or must fail is cold at any points")
    }

    @Test func editingTheCriteriaReRanksWithNoNewReading() {
        let found = [
            candidate("Alpha", stage: "yes", a: "yes", b: "yes"), candidate("Bravo", stage: "yes", a: "yes", b: "no"),
        ]
        var strict = criteria
        strict.hotAt = 2
        #expect(OutboundReview.rank(found, criteria: strict).map(\.triage.rating) == [.hot, .warm])
    }

    @Test func theQueriesKeepOnlyRulesThatExistAndWantSomething() {
        let rules = OutboundQueries.searchable(
            Criteria(rules: [
                Rule(id: "r_x", role: .must, test: .text(TextTest(says: "Seed.", wants: true))),
                Rule(id: "r_y", role: .minus, test: .text(TextTest(says: "Big.", wants: false))),
                Rule(id: "r_z", role: .plus, test: .text(TextTest(says: "Revenue.", wants: true))),
            ]))
        #expect(rules.map(\.id) == ["r_x", "r_z"])
        let reply = OutboundQueries.Reply(criteria: [
            .init(rule: "r_x", queries: ["a", "b", "c", "d", "e", "f", "  "]),
            .init(rule: "r_y", queries: ["avoid"]), .init(rule: "r_ghost", queries: ["ghost"]),
            .init(rule: "r_z", queries: ["A", "z1"]),
        ])
        let kept = OutboundQueries.kept(reply, rules: rules)
        #expect(kept.filter { $0.rule == "r_x" }.map(\.query) == ["a", "b", "c", "d", "e"], "at most five a rule")
        #expect(kept.filter { $0.rule == "r_z" }.map(\.query) == ["z1"], "a repeat of another rule's query is dropped")
    }

    // MARK: the offline eval

    private func saved(_ url: String, _ company: String, stage: String, quote: String) -> OutboundFixture.Saved {
        .init(
            url: url,
            candidates: [
                [
                    "company": company, "quote": quote, "r_stage": stage, "r_stage_quote": quote,
                    "r_traction": stage == "yes" ? "yes" : "unclear",
                    "r_traction_quote": stage == "yes" ? quote : "",
                ]
            ])
    }

    private func fixture(split: String = "dev", acornPage: String? = nil) -> OutboundFixture {
        let pages = [
            "https://a.example/acme": "Acme raised a seed round and sells to 40 clients.",
            "https://b.example/bolt": "Bolt Pay raised a Series D round.",
            "https://c.example/cyan": acornPage ?? "Cyan raised a seed round.",
        ]
        func deal(_ company: String, _ url: String, _ call: Rating) -> PastDeal {
            PastDeal(id: company, company: company, text: pages[url]!, url: url, call: call)
        }
        return OutboundFixture(
            split: split, criteria: .starter,
            deals: [
                deal("Acme", "https://a.example/acme", .hot), deal("Bolt Pay", "https://b.example/bolt", .cold),
                deal("Cyan", "https://c.example/cyan", .warm),
            ], pages: [.init(url: "https://d.example/delta", text: "Delta raised a seed round.")],
            saved: [
                saved("https://a.example/acme", "Acme", stage: "yes", quote: "raised a seed round"),
                saved("https://b.example/bolt", "Bolt Pay", stage: "no", quote: "raised a Series D round"),
                saved("https://c.example/cyan", "Cyan", stage: "yes", quote: "raised a seed round"),
                saved("https://d.example/delta", "Delta", stage: "yes", quote: "raised a seed round"),
            ], queries: 3, provider: .brave)
    }

    private func eval(_ fixture: OutboundFixture) async throws -> OutboundEval.Report {
        try await OutboundEval.run(fixture, model: ReplayModel(fixture.saved), store: try makeStore())
    }

    @Test func theEvalReportsRecallAndPrecisionAgainstTheInvestorsCallsWithItsLabel() async throws {
        let report = try await eval(fixture())
        #expect(report.label == "dev" && report.candidates == 4 && report.accepted == 2)
        #expect(report.acceptedFound == 2 && report.recall == 1)
        #expect((report.topRight, report.topWrong, report.topUnmarked) == (2, 1, 1))
        #expect(report.precision == 0.5, "Delta has no call: it counts as not right")
        #expect(abs(report.cost.totalUSD - (3 * 0.005 + 4 * 0.02)) < 1e-9)
        #expect(report.costPerAcceptedLead == report.cost.totalUSD / 2)
    }

    @Test func aLostAcceptedDealLowersRecallAndALabelIsRequired() async throws {
        let lost = try await eval(fixture(acornPage: "Cyan is a company."))
        #expect(lost.acceptedFound == 1 && lost.recall == 0.5, "the quote is not in the page, so no candidate")
        let held = try await eval(fixture(split: "held_out"))
        #expect(held.label == "held-out")
        await #expect(throws: OutboundEval.Failure.unlabelled) { try await eval(fixture(split: "test")) }
    }

    @Test func recallLooksOnlyAtTheTopHundredAndPrecisionAtTheTopTwenty() async throws {
        func crowded(accepted name: String) -> OutboundFixture {
            let extra = (0..<105).map { "Startup\(String(format: "%03d", $0))" }
            let text = "raised a seed round"
            return OutboundFixture(
                split: "dev", criteria: .starter,
                deals: [
                    PastDeal(id: "z", company: name, text: "\(name) \(text)", url: "https://z.example/z", call: .hot)
                ],
                pages: extra.map { .init(url: "https://s.example/\($0)", text: "\($0) \(text)") },
                saved: [saved("https://z.example/z", name, stage: "yes", quote: text)]
                    + extra.map { saved("https://s.example/\($0)", $0, stage: "yes", quote: text) })
        }
        let late = try await eval(crowded(accepted: "Zed Labs"))
        #expect(late.candidates == 106 && late.acceptedFound == 0 && late.recall == 0, "Zed Labs ranks 106th")
        #expect(late.topCount == 20 && late.topRight == 0 && late.precision == 0)
        let early = try await eval(crowded(accepted: "Aaa Labs"))
        #expect(early.acceptedFound == 1 && early.topRight == 1 && early.precision == 0.05, "Aaa Labs ranks first")
    }

    @Test func aFixtureFileWithOnlyTheRequiredKeysDecodesAndRuns() async throws {
        let json = """
            {"split":"held_out","criteria":{"hotAt":1,"rules":[{"id":"r_stage","role":"must","test":{"text":{"_0":{"says":"Raises a seed round.","wants":true}}}}]},
             "deals":[{"id":"1","company":"Acme","text":"Acme raised a seed round.","url":"https://a.example/acme","call":"hot"}],
             "saved":[{"url":"https://a.example/acme","candidates":[{"company":"Acme","quote":"raised a seed round","r_stage":"yes","r_stage_quote":"raised a seed round"}]}]}
            """
        let fixture = try JSONDecoder().decode(OutboundFixture.self, from: Data(json.utf8))
        let report = try await eval(fixture)
        #expect(report.label == "held-out" && report.recall == 1 && report.precision == 1 && fixture.provider == .brave)
    }
}
