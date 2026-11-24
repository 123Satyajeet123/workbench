import Foundation
import Testing

@testable import WorkbenchCore

/// Ranking and the queries the model writes.
@Suite struct OutboundReviewTests {
    private let criteria = Criteria(
        rules: [
            Rule(id: "r_stage", role: .must, test: .text(TextTest(says: "Raises a seed round.", wants: true))),
            Rule(id: "r_a", role: .plus, test: .text(TextTest(says: "Has revenue.", wants: true))),
            Rule(id: "r_b", role: .plus, test: .text(TextTest(says: "Has a repeat founder.", wants: true))),
        ], levels: Level.standard(topCut: 1))

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
        #expect(ranked.map(\.triage.rating) == ["hot", "hot", "hot", "warm", "cold"])
        #expect(ranked.map(\.triage.points) == [2, 1, 1, 0, 2], "a deal-breaker or must fail is cold at any points")
    }

    @Test func editingTheCriteriaReRanksWithNoNewReading() {
        let found = [
            candidate("Alpha", stage: "yes", a: "yes", b: "yes"), candidate("Bravo", stage: "yes", a: "yes", b: "no"),
        ]
        var strict = criteria
        strict.bestCut = 2
        #expect(OutboundReview.rank(found, criteria: strict).map(\.triage.rating) == ["hot", "warm"])
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
}
