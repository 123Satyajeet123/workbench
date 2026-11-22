import Foundation
import Testing

@testable import WorkbenchCore

private let india = Rule(id: "r_in", role: .must, test: .text(TextTest(says: "Based in India", wants: true)))
private let traction = Rule(id: "r_trac", role: .plus, test: .text(TextTest(says: "Shows revenue", wants: true)))
private let thesis = Criteria(rules: [india, traction])

private func reading(india inIndia: String, traction hasTraction: String) -> [String: String] {
    [
        "r_in": inIndia, "r_in_quote": "q", "r_in_reason": "r", "r_trac": hasTraction, "r_trac_quote": "q",
        "r_trac_reason": "r",
    ]
}

private func deal(_ company: String, call: Rating, india: String? = nil, traction: String = "yes") -> PastDeal {
    PastDeal(
        company: company, text: "\(company) pitch", call: call,
        reading: india.map { reading(india: $0, traction: traction) })
}

private let fixture = [
    deal("A", call: .hot, india: "yes"), deal("B", call: .hot, india: "yes"), deal("C", call: .hot, india: "no"),
    deal("D", call: .warm, india: "yes", traction: "no"), deal("E", call: .warm, india: "yes"),
    deal("F", call: .cold, india: "no"), deal("G", call: .cold, india: "yes", traction: "no"),
    deal("H", call: .cold, india: "no"), deal("I", call: .hot),
]

@Suite struct AgreementReportTests {
    private let report = AgreementReport(deals: fixture, criteria: thesis)

    @Test func theNumbersOnTheFixtureAreExact() {
        #expect(report.total == 8 && report.unread == 1)
        #expect(report.agreed == 5 && report.rate == 0.625)
        #expect(report.hotMissed == 1 && report.calledHot == 3)
    }

    @Test func theConfusionTableCountsEachPairOfCalls() {
        let pairs: [(Rating, Rating, Int)] = [
            (.hot, .hot, 2), (.hot, .warm, 0), (.hot, .cold, 1), (.warm, .hot, 1), (.warm, .warm, 1),
            (.warm, .cold, 0), (.cold, .hot, 0), (.cold, .warm, 1), (.cold, .cold, 2),
        ]
        for (called, rated, count) in pairs {
            #expect(report.count(called: called, rated: rated) == count, "\(called) called, \(rated) rated")
        }
        #expect(pairs.reduce(0) { $0 + $1.2 } == report.total)
    }

    @Test func theExactBinomialBoundsMatchAnIndependentCalculation() throws {
        #expect(abs(try #require(report.agreementFloor) - 0.3446231868540187) < 1e-9, "3 wrong of 8, 90 percent")
        #expect(abs(try #require(report.hotMissedCeiling) - 0.8041998943409083) < 1e-9, "1 missed of 3 hot")
    }

    @Test func everyNumberIsOnTheHeldOutSet() {
        #expect(report.split == .heldOut)
    }

    @Test func anEmptyReportHasNoRateAndNoBound() {
        let empty = AgreementReport(deals: [deal("I", call: .hot)], criteria: thesis)
        #expect(empty.rate == nil && empty.agreementFloor == nil && empty.hotMissedCeiling == nil)
    }

    @Test func theReportFollowsTheCriteriaWithoutAnotherReading() {
        var strict = thesis
        strict.hotAt = 2
        let stricter = AgreementReport(deals: fixture, criteria: strict)
        #expect(stricter.count(called: .hot, rated: .hot) == 0, "one plus rule cannot reach 2 points")
        #expect(stricter.agreed != report.agreed)
    }

    @Test func dealsNeedingReviewAreCounted() {
        let gap = PastDeal(company: "J", text: "t", call: .warm, reading: ["r_trac": "yes", "r_trac_quote": "q"])
        let withGap = AgreementReport(deals: fixture + [gap], criteria: thesis)
        #expect(report.needingReview == 3, "C, F and H: a plus passes while the must fails")
        #expect(withGap.needingReview == 4, "the must rule has no reading")
    }
}

@Suite struct HeldOutDealTests {
    private let day = WorkDay(containing: t0)
    private let pitch = "Zed Labs, Mumbai: 60 people, 4M seed, 300k MRR. Secret held-out wording."

    private func spec() -> HelperSpec {
        var spec = HelperSpec.dealIntake
        spec.criteria = thesis
        spec.examples = 5
        return spec
    }

    private func reply(quote: String) throws -> String {
        let item: [String: Any] = [
            "company": "Zed Labs", "sector": "x", "stage": "seed", "from": "", "cite": 1, "quote": quote,
            "r_in": "yes", "r_in_quote": "Mumbai", "r_in_reason": "Mumbai is in India.", "r_trac": "yes",
            "r_trac_quote": "300k MRR", "r_trac_reason": "Revenue is stated.",
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["items": [item]]), as: UTF8.self)
    }

    @Test func readingAPastDealKeepsRuleReadingsOnTheDealAndMakesNoItemAndNoMark() async throws {
        let store = try makeStore()
        let reader = AgreementReader(
            spec: spec(), model: RecordedModel(ScriptedModel(try reply(quote: "4M seed")), store: store))
        let read = try await reader.read(PastDeal(company: "Zed Labs", text: pitch, call: .hot), on: day)
        #expect(thesis.triage(try #require(read.reading)).rating == .hot)
        #expect(try store.queries.items(of: spec().task, day: day, scope: "agreement").isEmpty)
        #expect(try store.queries.items(of: spec().task, since: day.adding(days: -400)).isEmpty, "no item, so no mark")
    }

    @Test func aLiveReadingNeverSeesAPastDealAsAnExample() async throws {
        let store = try makeStore()
        let first = ScriptedModel(try reply(quote: "4M seed"))
        _ = try await AgreementReader(spec: spec(), model: RecordedModel(first, store: store))
            .read(PastDeal(company: "Zed Labs", text: pitch, call: .hot), on: day)
        let live = ScriptedModel(#"{"items":[]}"#)
        let line = Evidence(id: 1, start: day.start, line: "mail — Inbox: other deal", quotable: ["other deal"])
        _ = try await HelperReader(spec: spec(), model: RecordedModel(live, store: store))
            .read(
                day: day, scope: "", evidence: EvidenceSet(lines: [line]),
                marked: try store.queries.items(of: spec().task, since: day.adding(days: -400)))
        let input = try #require(live.inputs.withLock { $0.first })
        #expect(!input.contains("Zed") && !input.contains("Secret") && !input.contains("Examples the founder marked"))
    }

    @Test func theImproverSeesOnlyItemsOnDevDaysAndNeverAPastDeal() async throws {
        let store = try makeStore()
        let model = ScriptedModel(#"{"kind":"add","text":"Skip newsletters.","why":"w","cites":[1]}"#)
        let devDay = (1...60).map { day.adding(days: -$0) }.first { EvalSplit($0) == .dev }!
        let heldDay = (1...60).map { day.adding(days: -$0) }.first { EvalSplit($0) == .heldOut }!
        func wrong(_ id: Int64, on day: WorkDay) -> Item {
            var item = Item(
                id: id, task: spec().task, day: day, scope: "", source: .screenText, citeFirst: 1, citeLast: 1,
                start: day.start, end: day.start, fields: ["company": "C\(id)"], quote: "q\(id)", run: 1)
            item.state = .rejected
            return item
        }
        let marked = [wrong(1, on: devDay), wrong(2, on: devDay), wrong(3, on: devDay), wrong(99, on: heldDay)]
        _ = try await Improver(model: RecordedModel(model, store: store)).propose(spec: spec(), marked: marked)
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("[1] wrong") && !input.contains("[99]"), "a held-out day's item stays out")
        #expect(!input.contains("Zed") && !input.contains("Secret"), "a past deal is not an item at all")
    }
}
