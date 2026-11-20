import Foundation
import Testing

@testable import WorkbenchCore

private let employees = Rule(
    id: "r_emp", role: .plus,
    test: .number(NumberTest(measure: "employee count", unit: "people", comparison: .atLeast, low: 20)))
private let india = Rule(
    id: "r_in", role: .must, test: .text(TextTest(says: "Based in India", wants: true)))
private let gambling = Rule(
    id: "r_gamble", role: .dealBreaker, test: .text(TextTest(says: "Gambling or betting", wants: false)))
private let traction = Rule(
    id: "r_trac", role: .plus, test: .text(TextTest(says: "Shows revenue", wants: true)))
private let burn = Rule(
    id: "r_burn", role: .minus, test: .text(TextTest(says: "Burns cash with no revenue", wants: false)))

private let yes = "yes"
private let no = "no"

private func triage(_ criteria: Criteria, _ pairs: [String: String]) -> Triage { criteria.triage(pairs) }

private func answered(_ rule: Rule, _ answer: String) -> [String: String] {
    [rule.id: answer, rule.quoteKey: "q", rule.reasonKey: "because"]
}

@Suite struct NumberRuleTests {
    private let limit = Criteria(rules: [employees])

    @Test func aNumberRulePassesFailsAndIsUnknownOnAMissingNumber() {
        #expect(triage(limit, answered(employees, "45")).results[0].verdict == .pass)
        #expect(triage(limit, answered(employees, "12")).results[0].verdict == .fail)
        #expect(triage(limit, answered(employees, "")).results[0].verdict == .unknown, "empty answer")
        #expect(triage(limit, answered(employees, "about forty")).results[0].verdict == .unknown, "not a number")
        let unread = triage(limit, [:]).results[0]
        #expect(unread.verdict == .unknown && !unread.isRead, "no reading yet")
    }

    @Test func aMissingNumberNeverFailsAMustRule() {
        let must = Rule(id: "r_emp", role: .must, test: employees.test)
        let result = triage(Criteria(rules: [must]), answered(must, ""))
        #expect(result.rating != .cold && result.needsReview, "unknown holds at warm and asks for review")
        #expect(result.review == ["Employee count not found."])
    }

    @Test func eachComparisonHasItsBoundary() {
        func passes(_ comparison: Comparison, _ value: Double) -> Bool {
            NumberTest(measure: "n", unit: "", comparison: comparison, low: 20, high: 50).passes(value)
        }
        #expect(!passes(.above, 20) && passes(.above, 21))
        #expect(passes(.atLeast, 20) && !passes(.atLeast, 19))
        #expect(!passes(.below, 20) && passes(.below, 19))
        #expect(passes(.atMost, 20) && !passes(.atMost, 21))
        #expect(passes(.between, 20) && passes(.between, 50) && !passes(.between, 19) && !passes(.between, 51))
    }

    @Test func thousandsCommasAreNumbersAndWordsAreNot() {
        #expect(Criteria.number("1,200") == 1200)
        #expect(Criteria.number("12 crore") == nil)
    }
}

@Suite struct CombineTableTests {
    private func rating(_ criteria: Criteria, _ pairs: [String: String]) -> Rating {
        triage(criteria, pairs).rating
    }

    @Test func aDealBreakerForcesColdWhateverElsePasses() {
        let criteria = Criteria(rules: [gambling, traction, employees])
        let pass = answered(traction, yes).and(answered(employees, "90"))
        #expect(rating(criteria, pass.and(answered(gambling, no))) == .hot)
        let result = triage(criteria, pass.and(answered(gambling, yes)))
        #expect(result.rating == .cold)
        #expect(result.decidedBy == ["r_gamble"])
        #expect(result.review == ["The rules point both ways."], "a plus passes while a hard stop fails")
    }

    @Test func aFailedMustIsColdAndAnUnknownMustHoldsAtWarm() {
        let criteria = Criteria(rules: [india, traction])
        #expect(rating(criteria, answered(india, no).and(answered(traction, yes))) == .cold)
        let held = triage(criteria, answered(traction, yes))
        #expect(held.rating == .warm && held.needsReview, "must not read yet, so hot is held at warm")
        let clear = triage(criteria, answered(india, yes).and(answered(traction, yes)))
        #expect(clear.rating == .hot && !clear.needsReview)
    }

    @Test func pointsDecideTheRestByTheStatedTable() {
        let criteria = Criteria(rules: [traction, employees, burn])
        let one = answered(traction, yes).and(answered(employees, "5"))
        #expect(rating(criteria, one.and(answered(burn, no))) == .hot, "1 point")
        #expect(rating(criteria, answered(traction, no).and(answered(burn, no))) == .warm, "0 points")
        #expect(rating(criteria, answered(burn, yes)) == .cold, "-1 point")
        #expect(rating(criteria, one.and(answered(burn, yes))) == .warm, "1 - 1")
        var strict = criteria
        strict.hotAt = 2
        #expect(rating(strict, one.and(answered(employees, "50"))) == .hot, "2 points reach hotAt 2")
        #expect(rating(strict, one) == .warm, "1 point is below hotAt 2")
        #expect(criteria.table.count == 6 && criteria.table[3].contains("Points of 1 or more"))
    }

    @Test func anAvoidRuleFailsWhenTheDealMatchesIt() {
        #expect(triage(Criteria(rules: [gambling]), answered(gambling, yes)).results[0].verdict == .fail)
        #expect(triage(Criteria(rules: [gambling]), answered(gambling, no)).results[0].verdict == .pass)
        #expect(triage(Criteria(rules: [gambling]), answered(gambling, "unclear")).results[0].verdict == .unknown)
    }

    @Test func aMinusWithAPlusConflictsAndAsksForReview() {
        let result = triage(
            Criteria(rules: [traction, burn]), answered(traction, yes).and(answered(burn, yes)))
        #expect(result.rating == .warm && result.review == ["The rules point both ways."])
    }
}

@Suite struct CriteriaVersionTests {
    private let day = WorkDay(containing: t0)

    private func instructions(_ criteria: Criteria) throws -> String {
        var spec = HelperSpec.dealIntake
        spec.criteria = criteria
        return HelperReader(spec: spec, model: RecordedModel(ScriptedModel("{}"), store: try makeStore())).instructions
    }

    @Test func everyRuleEditIsANewPromptVersion() throws {
        let base = Criteria(rules: [employees, india])
        let edits: [String: Criteria] = [
            "limit": base.replacing(
                "r_emp",
                with: Rule(
                    id: "r_emp", role: .plus,
                    test: .number(.init(measure: "employee count", unit: "people", comparison: .atLeast, low: 30)))),
            "role": base.replacing("r_in", with: Rule(id: "r_in", role: .dealBreaker, test: india.test)),
            "words": base.replacing(
                "r_in", with: Rule(id: "r_in", role: .must, test: .text(.init(says: "Based in Pune", wants: true)))),
            "added": base.adding(gambling), "removed": base.removing("r_in"),
            "table": Criteria(rules: base.rules, hotAt: 2),
        ]
        let original = try instructions(base)
        for (name, edited) in edits {
            #expect(try instructions(edited) != original, "\(name) must change the instructions")
        }
        #expect(try instructions(base) == original, "the same criteria give the same version")
    }

    @Test func onlyAChangeOfWhatIsJudgedGivesARuleANewId() {
        let base = Criteria(rules: [employees, india])
        let limit = Rule(
            id: "x", role: .minus,
            test: .number(.init(measure: "employee count", unit: "people", comparison: .below, low: 3)))
        #expect(base.replacing("r_emp", with: limit).rules[0].id == "r_emp", "a limit and a role need no new reading")
        let flipped = Rule(id: "x", role: .must, test: .text(.init(says: "Based in India", wants: false)))
        #expect(base.replacing("r_in", with: flipped).rules[1].id == "r_in", "want to avoid needs no new reading")
        let words = Rule(id: "x", role: .must, test: .text(.init(says: "Based in Goa", wants: true)))
        #expect(base.replacing("r_in", with: words).rules[1].id != "r_in")
        let measure = Rule(
            id: "x", role: .plus,
            test: .number(.init(measure: "headcount", unit: "people", comparison: .atLeast, low: 20)))
        #expect(base.replacing("r_emp", with: measure).rules[0].id != "r_emp")
    }

    @Test func savingCriteriaMakesANewMachineVersionAndAProblemIsRefused() throws {
        let store = try makeStore()
        let machine = try store.createMachine(from: .dealIntake, name: "Deal intake")
        let edited = Criteria(rules: [employees])
        try store.setCriteria(machine, edited)
        let saved = try #require(try store.queries.machines().first)
        #expect(saved.spec.criteria == edited)
        try store.setCriteria(saved, Criteria(rules: [Rule(role: .must, test: .text(.init(says: " ", wants: true)))]))
        #expect(try store.queries.machines().first?.spec.criteria == edited, "a rule with no words is refused")
    }

    @Test func aSpecSavedBeforeCriteriaStillOpens() throws {
        let old = HelperSpec.pages
        let json = try JSONEncoder().encode(old)
        #expect(try JSONDecoder().decode(HelperSpec.self, from: json).criteria == nil)
    }
}

@Suite struct RuleReadingTests {
    private let day = WorkDay(containing: t0)
    private let text =
        "Acme builds payroll software in Pune. We are 45 people and raising a 2M seed. Revenue is 40k MRR."
    private var evidence: EvidenceSet {
        EvidenceSet(lines: [Evidence(id: 1, start: day.start, line: "mail — Inbox: \(text)", quotable: [text])])
    }

    private func read(_ criteria: Criteria, _ rules: [String: String]) async throws -> (Item?, ScriptedModel) {
        var spec = HelperSpec.dealIntake
        spec.criteria = criteria
        var item: [String: Any] = [
            "company": "Acme", "sector": "payroll", "stage": "seed", "from": "", "cite": 1,
            "quote": "raising a 2M seed",
        ]
        item.merge(rules) { _, rule in rule }
        let data = try JSONSerialization.data(withJSONObject: ["items": [item]])
        let model = ScriptedModel(String(decoding: data, as: UTF8.self))
        let reader = HelperReader(spec: spec, model: RecordedModel(model, store: try makeStore()))
        return (try await reader.read(day: day, scope: "", evidence: evidence).items.first, model)
    }

    @Test func theModelIsNeverAskedForTheCallOrToldALimit() throws {
        var spec = HelperSpec.dealIntake
        spec.criteria = Criteria(rules: [employees, india])
        let reader = HelperReader(spec: spec, model: RecordedModel(ScriptedModel("{}"), store: try makeStore()))
        let schema = try reader.schema.jsonText
        #expect(!schema.contains("\"rating\"") && schema.contains("r_emp_quote") && schema.contains("r_in_reason"))
        #expect(!reader.instructions.contains("at least 20") && !reader.instructions.contains("must"))
        #expect(reader.instructions.contains("you do not rate the deal"))
    }

    @Test func aRuleKeepsItsNumberAndVerifiedQuoteAndCodeRatesIt() async throws {
        let criteria = Criteria(rules: [employees, india])
        let (item, _) = try await read(
            criteria,
            [
                "r_emp": "45", "r_emp_quote": "We are 45 people", "r_in": "yes", "r_in_quote": "in Pune",
                "r_in_reason": "Pune is in India.",
            ])
        let kept = try #require(item)
        let result = criteria.triage(kept.fields)
        #expect(result.rating == .hot)
        #expect(result.results[0].number == 45 && result.results[0].quote == "We are 45 people")
        #expect(result.results[1].reason == "Pune is in India.")
    }

    @Test func aQuoteNotInThePageMakesTheRuleUnknownButKeepsTheDeal() async throws {
        let criteria = Criteria(rules: [employees, india])
        let (item, _) = try await read(
            criteria,
            [
                "r_emp": "45", "r_emp_quote": "We employ 45", "r_in": "no", "r_in_quote": "based in Paris",
                "r_in_reason": "invented",
            ])
        let result = criteria.triage(try #require(item).fields)
        #expect(result.results.map(\.verdict) == [.unknown, .unknown], "no verified quote, no verdict")
        #expect(result.results.allSatisfy(\.isRead) && result.rating == .warm && result.needsReview)
    }

    @Test func aRuleAddedAfterTheReadingReadsAsNotYetReadAndIsNotAFail() async throws {
        let (item, _) = try await read(Criteria(rules: [employees]), ["r_emp": "45", "r_emp_quote": "45 people"])
        let later = Criteria(rules: [employees, india])
        let result = later.triage(try #require(item).fields)
        #expect(result.results.map(\.isRead) == [true, false] && result.results[1].verdict == .unknown)
        #expect(result.rating == .warm, "an unread must holds the deal at warm")
    }

    @Test func theScoredItemCarriesTheCallAndFollowsTheCriteriaNow() async throws {
        let criteria = Criteria(rules: [employees])
        let (item, _) = try await read(criteria, ["r_emp": "45", "r_emp_quote": "45 people"])
        var spec = HelperSpec.dealIntake
        spec.criteria = criteria
        let kept = try #require(item)
        #expect(kept["rating"] == "" && spec.scored(kept)["rating"] == "hot", "the call is never stored")
        spec.criteria?.rules[0].test = .number(
            .init(measure: "employee count", unit: "people", comparison: .atLeast, low: 90))
        #expect(spec.scored(kept)["rating"] == "warm", "same reading, a new limit, no model call")
    }

    @Test func thePreviewRescoresInCodeWithNoModelCall() async throws {
        let current = Criteria(rules: [employees])
        let (item, model) = try await read(current, ["r_emp": "45", "r_emp_quote": "45 people"])
        let calls = model.inputs.withLock { $0.count }
        let stricter = current.replacing(
            "r_emp",
            with: Rule(
                role: .plus,
                test: .number(.init(measure: "employee count", unit: "people", comparison: .atLeast, low: 90))))
        let preview = CriteriaPreview(items: [try #require(item)], title: "company", current: current, edited: stricter)
        #expect(
            preview.changed.map(\.title) == ["Acme"] && preview.changed[0].was == .hot
                && preview.changed[0].now == .warm)
        #expect(preview.unread == 0 && model.inputs.withLock { $0.count } == calls)
        let reworded = current.replacing(
            "r_emp",
            with: Rule(
                role: .plus, test: .number(.init(measure: "headcount", unit: "people", comparison: .atLeast, low: 20))))
        #expect(
            CriteriaPreview(items: [try #require(item)], title: "company", current: current, edited: reworded).unread
                == 1)
    }
}

extension Dictionary where Key == String, Value == String {
    /// The readings of two rules together.
    fileprivate func and(_ other: [String: String]) -> [String: String] { merging(other) { _, new in new } }
}
