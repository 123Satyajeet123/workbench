import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct CertificateTests {
    private func answers(_ count: Int, wrong: Bool = false, chance: Double = RunSettings.standard.pickChance)
        -> [Certificate
        .Answer]
    {
        Array(repeating: Certificate.Answer(wrong: wrong, chance: chance), count: count)
    }

    private func status(_ answers: [Certificate.Answer]) -> Certificate.Status { Certificate(answers: answers).status }

    @Test func theBarAndTheAllowedRateAre90PercentSureAndAtMost10PercentWrong() {
        #expect(RunSettings.standard.allowedWrong == 0.1 && RunSettings.standard.confidence == 0.9)
        #expect(abs(RunSettings.standard.threshold - 10) < 1e-9)
    }

    /// Reference values from an independent computation (Python): the mean over the nine bets of the product
    /// of 1 + bet / 0.9 × share × (0.1 − wrong).
    @Test func theWealthMatchesAnIndependentComputation() {
        var wealth = Certificate.Wealth()
        for answer in answers(35, chance: 0.1) { wealth.add(answer) }
        #expect(abs(wealth.value - 9.902993868959816) < 1e-9)
        wealth.add(Certificate.Answer(wrong: false, chance: 0.1))
        #expect(abs(wealth.value - 10.68198004209384) < 1e-9)
        var mixed = Certificate.Wealth()
        let sequence =
            answers(30, chance: 1) + answers(1, wrong: true, chance: 0.1) + answers(10, chance: 0.2)
        for answer in sequence { mixed.add(answer) }
        #expect(abs(mixed.value - 0.8454980895134014) < 1e-9)
    }

    @Test func thirtySixRightAnswersEarnItAndThirtyFiveDoNot() {
        guard case .earned(let bound) = status(answers(36)) else {
            Issue.record("36 right answers at the heaviest weight should earn it")
            return
        }
        #expect(bound <= RunSettings.standard.allowedWrong)
        #expect(status(answers(35)) == .needsMore(1))
        #expect(status([]) == .needsMore(36))
    }

    @Test func aWrongAnswerRaisesHowManyMoreRightAnswersAreNeeded() throws {
        #expect(status(answers(1, wrong: true)) == .needsMore(54))
        guard case .needsMore(let more) = status(answers(5, wrong: true) + answers(45)) else {
            Issue.record("5 wrong of 50 should not earn it")
            return
        }
        #expect(status(answers(5, wrong: true) + answers(45 + more)) != .needsMore(1))
        guard case .earned = status(answers(5, wrong: true) + answers(45 + more)) else {
            Issue.record("the promised number of right answers should earn it")
            return
        }
        #expect(status(answers(5, wrong: true) + answers(45 + more - 1)) == .needsMore(1))
    }

    @Test func theEarnedBoundIsBelowTheAllowedRateAndFallsAsRightAnswersCome() throws {
        guard case .earned(let atForty) = status(answers(40)), case .earned(let atSixty) = status(answers(60)) else {
            Issue.record("40 and 60 right answers should earn it")
            return
        }
        #expect(abs(atForty - 0.08849956152034794) < 1e-6)
        #expect(abs(atSixty - 0.06010857689325347) < 1e-6)
        #expect(atSixty < atForty && atForty < RunSettings.standard.allowedWrong)
    }

    @Test func aHeavyWrongAnswerKeepsItFromEarningWhereAPlainCountWouldEarn() {
        let oneHeavyWrong = answers(60, chance: 1) + answers(1, wrong: true, chance: 0.1)
        #expect(ClopperPearson.upperBound(wrong: 1, of: 61) <= RunSettings.standard.allowedWrong, "a plain count earns")
        guard case .needsMore(let afterHeavy) = status(oneHeavyWrong) else {
            Issue.record("one wrong answer for ten items should keep it from earning")
            return
        }
        guard case .needsMore(let afterLight) = status(answers(60, chance: 1) + answers(1, wrong: true, chance: 1))
        else {
            Issue.record("60 answers for one item each should not earn it")
            return
        }
        #expect(afterHeavy > afterLight)
    }

    @Test func heavyRightAnswersAmongLightWrongOnesEarnWhereAPlainCountDoesNot() {
        let heavyRight = answers(40, chance: 0.1)
        let lightWrong = answers(3, wrong: true, chance: 1)
        #expect(
            ClopperPearson.upperBound(wrong: 3, of: 43) > RunSettings.standard.allowedWrong,
            "a plain count does not earn")
        guard case .earned = status(heavyRight + lightWrong) else {
            Issue.record("40 right answers for ten items each outweigh 3 wrong answers for one item each")
            return
        }
    }

    @Test func aWeightAboveTheHeaviestCountsAsTheHeaviest() {
        let capped = Certificate.Answer(wrong: false, chance: 1 / RunSettings.standard.heaviestWeight)
        let beyond = Certificate.Answer(wrong: false, chance: 0.001)
        let lighter = Certificate.Answer(wrong: false, chance: 0.2)
        var (atEdge, past, below) = (Certificate.Wealth(), Certificate.Wealth(), Certificate.Wealth())
        atEdge.add(capped)
        past.add(beyond)
        below.add(lighter)
        #expect(atEdge.value == past.value)
        #expect(below.value < atEdge.value)
        #expect(Certificate.Answer(wrong: true, chance: 0.001).share(pickChance: RunSettings.standard.pickChance) == 1)
    }

    @Test func aWrongAnswerNeverTakesTheWealthToZero() {
        var wealth = Certificate.Wealth()
        for _ in 0..<200 { wealth.add(Certificate.Answer(wrong: true, chance: 0.1)) }
        #expect(wealth.value > 0)
    }

    @Test func aStatusSurvivesBeingSentAsJSON() throws {
        for status in [Certificate.Status.needsMore(7), .earned(bound: 0.0625)] {
            let decoded = try JSONDecoder().decode(Certificate.Status.self, from: JSONEncoder().encode(status))
            #expect(decoded == status)
        }
    }

    @Test func onlyAuditAnswersOnHeldOutDaysCount() async throws {
        let days = (0..<200).map { WorkDay(containing: t0.addingTimeInterval(Double($0) * 86_400)) }
        let heldOut = days.filter { EvalSplit($0) == .heldOut }.prefix(2)
        let dev = try #require(days.first { EvalSplit($0) == .dev })
        let store = try makeStore()
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let (_, run) = try await model.generate(
            HelperReader.Reply.self, schema: .object([.init("items", .array(.string))]), task: "day.timeline",
            instructions: "v1", input: "x", holding: [])
        for (day, mark) in zip(Array(heldOut) + [dev], [Mark.confirmed, .rejected, .rejected]) {
            let items = (0..<2).map { index in
                Item(
                    task: "day.timeline", day: day, scope: "", source: .screen, citeFirst: Int64(index),
                    citeLast: Int64(index), start: day.start.addingTimeInterval(Double(index) * 600),
                    end: day.start.addingTimeInterval(Double(index) * 600 + 300), fields: ["task": "t\(index)"],
                    quote: "q", run: run)
            }
            try store.saveReading(
                .init(items: items, dropped: 0, run: run), of: .timeline, day: day, scope: "", grant: grant(.screen),
                isAudited: { $0 == 0 })
            let saved = try store.queries.items(of: "day.timeline", day: day, scope: "")
            for item in saved { try store.mark(item: try #require(item.id), as: mark) }
        }
        let quality = try #require(store.queries.quality().first)
        let given = [
            Certificate.Answer(wrong: false, chance: RunSettings.standard.pickChance),
            Certificate.Answer(wrong: true, chance: RunSettings.standard.pickChance),
        ]
        #expect(quality.heldOutAudit == Certificate(answers: given))
        #expect(quality.audited.marks == 3)
        #expect(quality.all.marked == 6)
    }
}

@Suite struct ClopperPearsonTests {
    /// Reference values from an independent bisection on the binomial CDF (Python, exact integer binomials).
    @Test(arguments: [
        (0, 22, 0.099372), (0, 21, 0.103849), (1, 38, 0.098547), (3, 60, 0.107965), (5, 50, 0.177618), (0, 1, 0.9),
    ])
    func theUpperBoundMatchesTheExactBinomial(wrong: Int, answers: Int, expected: Double) {
        #expect(abs(ClopperPearson.upperBound(wrong: wrong, of: answers) - expected) < 1e-5)
    }
}
