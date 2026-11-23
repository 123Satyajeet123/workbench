import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct ExemplarTests {
    private let today = WorkDay(containing: t0)
    private var devDays: [WorkDay] { (1...30).map { today.adding(days: -$0) }.filter { DevHalf($0) == .learn } }
    private var trialDay: WorkDay { (1...30).map { today.adding(days: -$0) }.first { DevHalf($0) == .trial }! }
    private var heldOut: WorkDay { (1...30).map { today.adding(days: -$0) }.first { EvalSplit($0) == .heldOut }! }

    private func item(_ quote: String, _ state: Mark, on day: WorkDay) -> Item {
        var item = Item(
            task: "day.timeline", day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1, start: day.start,
            end: day.start, fields: ["task": quote, "project": ""], quote: quote, run: 1)
        item.state = state
        return item
    }

    /// The day being read is the newest training day, so only the rule, not age, can keep its item out.
    private var marked: [Item] {
        [
            item("same day", .confirmed, on: devDays[0]), item("right new", .confirmed, on: devDays[1]),
            item("right old", .confirmed, on: devDays[3]), item("wrong new", .rejected, on: devDays[1]),
            item("wrong older", .rejected, on: devDays[2]), item("held-out right", .confirmed, on: heldOut),
            item("unmarked", .proposed, on: devDays[1]), item("trial right", .confirmed, on: trialDay),
        ]
    }

    @Test func examplesComeOnlyFromMarkedTrainingDaysOtherThanTheDayRead() {
        let picked = Exemplars.pick(marked, for: devDays[0], count: 4).map(\.quote)
        #expect(picked == ["right new", "right old", "wrong new", "wrong older"])
    }

    @Test func atMostHalfAreWrongNewestFirstAndNoneWhenOff() {
        #expect(Exemplars.pick(marked, for: today, count: 3).map(\.quote) == ["same day", "right new", "wrong new"])
        #expect(Exemplars.pick(marked, for: today, count: 0).isEmpty)
        let noTraining = marked.filter { $0.quote == "held-out right" || $0.quote == "trial right" }
        #expect(
            Exemplars.pick(noTraining, for: today, count: 5).isEmpty, "held-out and trial items never become examples")
    }
}

@Suite struct ExemplarReaderTests {
    @Test func turningExamplesOnIsANewVersionAndTheyComeBeforeTheDay() async throws {
        let store = try makeStore()
        let today = WorkDay(containing: t0)
        let other = (1...30).map { today.adding(days: -$0) }.first { DevHalf($0) == .learn }!
        var withExamples = HelperSpec.timeline
        withExamples.examples = 2
        #expect(
            HelperReader(spec: withExamples, model: RecordedModel(ScriptedModel("{}"), store: store)).instructions
                != HelperReader(spec: .timeline, model: RecordedModel(ScriptedModel("{}"), store: store)).instructions)
        var right = Item(
            task: "day.timeline", day: other, scope: "", source: .screen, citeFirst: 1, citeLast: 1, start: other.start,
            end: other.start, fields: ["task": "Review the PR"], quote: "PR #12", run: 1)
        right.state = .confirmed
        let scripted = ScriptedModel(#"{"items":[]}"#)
        let reader = HelperReader(spec: withExamples, model: RecordedModel(scripted, store: store))
        let evidence = EvidenceSet(lines: [
            Evidence(id: 1, start: today.start, line: "App — window", quotable: ["window"])
        ])
        _ = try await reader.read(day: today, scope: "", evidence: evidence, marked: [right])
        let input = try #require(scripted.inputs.withLock { $0.first })
        #expect(input.hasPrefix("Examples the founder marked on other days:\n- right: task=Review the PR"))
        #expect(input.contains("Work day: \(today)"))
        let off = ScriptedModel(#"{"items":[]}"#)
        _ = try await HelperReader(spec: .timeline, model: RecordedModel(off, store: store))
            .read(day: today, scope: "", evidence: evidence, marked: [right])
        #expect(!(off.inputs.withLock { $0.first } ?? "").contains("Examples"), "no policy, no examples")
    }
}
