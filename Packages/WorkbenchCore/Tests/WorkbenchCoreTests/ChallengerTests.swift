import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct ChallengerTests {
    private let day = WorkDay(containing: t0)

    private func item(_ quote: String, minutes: Double, _ state: Mark = .proposed, task: String = "day.timeline")
        -> Item
    {
        Item(
            task: task, day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1,
            start: day.start.addingTimeInterval(minutes * 60), end: day.start.addingTimeInterval(minutes * 60 + 600),
            fields: ["task": quote], quote: quote, state: state, run: 1)
    }

    @Test func agreementKeepsMarksAndDifferencesAreCountedBothWays() {
        let current = [
            item("A", minutes: 0, .confirmed), item("B", minutes: 60, .rejected), item("C", minutes: 120, .confirmed),
        ]
        let trial = Trial.task(of: "day.timeline")
        let challenger = [item("A2", minutes: 0, task: trial), item("D", minutes: 300, .confirmed, task: trial)]
        let result = Trial(current: current, challenger: challenger, citation: .range)
        #expect(result.same == 1)
        #expect(result.added.map(\.quote) == ["D"])
        #expect(result.dropped.map(\.quote) == ["B", "C"])
        #expect(result.better == 2 && result.worse == 1 && result.waiting == 0)
    }

    @Test func theVerdictNeedsAOneSidedSplitNotAPercentage() {
        func verdict(better: Int, worse: Int) -> Trial.Verdict {
            let current =
                (0..<better).map { item("wrong\($0)", minutes: Double($0) * 20, .rejected) }
                + (0..<worse).map { item("right\($0)", minutes: 1000 + Double($0) * 20, .confirmed) }
            return Trial(current: current, challenger: [], citation: .range).verdict
        }
        #expect(verdict(better: 4, worse: 0) == .better)
        #expect(verdict(better: 3, worse: 0) == .notSure)
        #expect(verdict(better: 6, worse: 2) == .notSure)
        #expect(verdict(better: 9, worse: 2) == .better)
        #expect(verdict(better: 0, worse: 5) == .worse)
        #expect(verdict(better: 0, worse: 0) == .notSure)
        #expect(abs(Binomial.atLeast(4, of: 4) - 0.0625) < 1e-12)
    }

    @Test func aTrialTaskMapsBackToItsMachine() {
        #expect(Trial.task(of: "team.ledger") == "team.ledger#trial")
        #expect(Trial.isTrial("team.ledger#trial") && !Trial.isTrial("team.ledger"))
        #expect(Trial.machineTask(of: "team.ledger#trial") == "team.ledger")
    }
}
