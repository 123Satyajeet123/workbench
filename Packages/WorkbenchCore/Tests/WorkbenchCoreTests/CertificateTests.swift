import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct CertificateTests {
    /// Reference values from an independent bisection on the binomial CDF (Python, exact integer binomials).
    @Test(arguments: [
        (0, 22, 0.099372), (0, 21, 0.103849), (1, 38, 0.098547), (3, 60, 0.107965), (5, 50, 0.177618), (0, 1, 0.9),
    ])
    func theUpperBoundMatchesTheExactBinomial(wrong: Int, answers: Int, expected: Double) {
        #expect(abs(Certificate.upperBound(wrong: wrong, of: answers) - expected) < 1e-5)
    }

    @Test func twentyTwoRightAnswersEarnItAndTwentyOneDoNot() {
        guard case .earned(let bound) = Certificate(answers: 22, wrong: 0).status else {
            Issue.record("22 right answers should earn it")
            return
        }
        #expect(bound < 0.1)
        #expect(Certificate(answers: 21, wrong: 0).status == .needsMore(1))
        #expect(Certificate(answers: 0, wrong: 0).status == .needsMore(22))
        #expect(Certificate.fewestAnswers(wrong: 1) == 38)
    }

    @Test func aWrongAnswerRaisesHowManyMoreRightAnswersAreNeeded() {
        #expect(Certificate(answers: 38, wrong: 1).status != .needsMore(1))
        #expect(Certificate(answers: 37, wrong: 1).status == .needsMore(1))
        guard case .needsMore(let more) = Certificate(answers: 50, wrong: 5).status else {
            Issue.record("5 wrong of 50 should not earn it")
            return
        }
        #expect(more > 0)
        #expect(Certificate.upperBound(wrong: 5, of: 50 + more) <= Certificate.allowedWrong)
        #expect(Certificate.upperBound(wrong: 5, of: 50 + more - 1) > Certificate.allowedWrong)
    }

    @Test func onlyAuditAnswersOnHeldOutDaysCount() async throws {
        let days = (0..<200).map { WorkDay(containing: t0.addingTimeInterval(Double($0) * 86_400)) }
        let heldOut = days.filter { EvalSplit($0) == .heldOut }.prefix(2)
        let dev = try #require(days.first { EvalSplit($0) == .dev })
        let store = try makeStore()
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let (_, run) = try await model.generate(
            HelperReader.Reply.self, schema: .object([.init("items", .array(.string))]), task: "day.timeline",
            instructions: "v1", input: "x")
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
                pick: { _ in 0 })
            let saved = try store.queries.items(of: "day.timeline", day: day, scope: "")
            for item in saved { try store.mark(item: try #require(item.id), as: mark) }
        }
        let quality = try #require(store.queries.quality().first)
        #expect(quality.heldOutAudit == Certificate(answers: 2, wrong: 1))
        #expect(quality.audited.marks == 3)
        #expect(quality.all.marked == 6)
    }
}
