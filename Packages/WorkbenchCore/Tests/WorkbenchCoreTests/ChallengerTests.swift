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

    @Test func theVerdictComesFromMarksInTheOrderTheyCame() {
        let current =
            (0..<9).map { item("wrong\($0)", minutes: Double($0) * 20, .rejected) }
            + (0..<2).map { item("right\($0)", minutes: 1000 + Double($0) * 20, .confirmed) }
        let ids = Dictionary(uniqueKeysWithValues: current.indices.map { (Int64($0 + 1), $0) })
        var numbered = current
        for (id, index) in ids { numbered[index].id = id }
        let winsFirst = Dictionary(uniqueKeysWithValues: (1...11).map { (Int64($0), Int64($0)) })
        // Items 1–9 are the wins, 10–11 the losses; here the two losses were marked first.
        var lossesFirst: [Int64: Int64] = [10: 1, 11: 2]
        for id in Int64(1)...9 { lossesFirst[id] = id + 2 }
        let early = Trial(current: numbered, challenger: [], citation: .range, markOrder: winsFirst)
        let late = Trial(current: numbered, challenger: [], citation: .range, markOrder: lossesFirst)
        #expect(Array(early.outcomes.prefix(2)) == [true, true])
        #expect(Array(late.outcomes.prefix(2)) == [false, false])
        #expect(early.verdict == .better)
        #expect(late.verdict == .notSure)
    }
}

@Suite struct EProcessTests {
    @Test func aRunNeedsSevenStraightWinsAtTheDefaultThresholdAndMoreWhenMoreChallengersShareIt() {
        #expect(EProcess.threshold(challengers: 1) == 20 && EProcess.threshold(challengers: 2) == 40)
        #expect(EProcess.verdict(Array(repeating: true, count: 6), threshold: 20) == .notSure)
        #expect(EProcess.verdict(Array(repeating: true, count: 7), threshold: 20) == .better)
        #expect(EProcess.verdict(Array(repeating: false, count: 7), threshold: 20) == .worse)
        #expect(EProcess.verdict(Array(repeating: true, count: 7), threshold: 40) == .notSure)
        #expect(EProcess.verdict([true, true, true, true, true, true, false, false], threshold: 20) == .notSure)
        #expect(EProcess.verdict([], threshold: 20) == .notSure)
    }
}

@Suite struct TrialTaskTests {
    @Test func aTrialTaskMapsBackToItsMachine() {
        #expect(Trial.task(of: "team.ledger") == "team.ledger#trial")
        #expect(Trial.isTrial("team.ledger#trial") && !Trial.isTrial("team.ledger"))
        #expect(Trial.machineTask(of: "team.ledger#trial") == "team.ledger")
    }
}
