import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct ProposerTests {
    private let devDays = (1...40).map { WorkDay(containing: t0).adding(days: -$0) }.filter { EvalSplit($0) == .dev }
    private let heldOutDay = (1...40).map { WorkDay(containing: t0).adding(days: -$0) }.first {
        EvalSplit($0) == .heldOut
    }!

    private func item(_ id: Int64, _ state: Mark, on day: WorkDay, quote: String) -> Item {
        var item = Item(
            id: id, task: "day.timeline", day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1,
            start: day.start, end: day.start.addingTimeInterval(600), fields: ["task": quote], quote: quote, run: 1)
        item.state = state
        return item
    }

    private var marked: [Item] {
        [
            item(1, .rejected, on: devDays[0], quote: "Lunch"), item(2, .rejected, on: devDays[1], quote: "Coffee"),
            item(3, .rejected, on: devDays[2], quote: "Break"), item(4, .confirmed, on: devDays[0], quote: "Write PR"),
            item(9, .rejected, on: heldOutDay, quote: "Secret held-out"),
        ]
    }

    private func improver(_ reply: String) throws -> (Improver, ScriptedModel) {
        let scripted = ScriptedModel(reply)
        return (Improver(model: RecordedModel(scripted, store: try makeStore())), scripted)
    }

    @Test func aCitedSmallEditIsKeptAndHeldOutItemsNeverReachTheModel() async throws {
        let (improver, scripted) = try improver(
            #"{"kind":"add","text":"Leave out meals and breaks.","why":"Three wrong blocks were breaks","cites":[1,2,3]}"#
        )
        let (edit, run) = try await improver.propose(spec: .timeline, marked: marked)
        #expect(run != nil)
        let kept = try #require(edit)
        #expect(kept.apply(to: "Join windows.") == "Join windows. Leave out meals and breaks.")
        let input = try #require(scripted.inputs.withLock { $0.first })
        #expect(input.contains("[1] wrong task=Lunch") && input.contains("[4] right task=Write PR"))
        #expect(!input.contains("Secret held-out"))
    }

    @Test func withTooFewWrongItemsNoCallIsMade() async throws {
        let (improver, scripted) = try improver(#"{"kind":"none","text":"","why":"","cites":[]}"#)
        let few = marked.filter { $0.id != 3 }
        let (edit, run) = try await improver.propose(spec: .timeline, marked: few)
        #expect(edit == nil && run == nil && scripted.inputs.withLock { $0.isEmpty })
    }

    @Test func anEditThatCitesWhatItWasNotGivenRemovesWhatTheBriefLacksOrGrowsTooMuchIsDropped() {
        let given: Set<Int64> = [1, 2, 3, 4]
        let brief = "Join windows into blocks. Leave out breaks."
        func reply(_ kind: String, _ text: String, cites: [Int64] = [1]) -> Improver.Reply {
            Improver.Reply(kind: kind, text: text, why: "w", cites: cites)
        }
        #expect(Improver.checked(reply("add", "Name the project."), brief: brief, given: given) != nil)
        #expect(Improver.checked(reply("add", "Name the project.", cites: [9]), brief: brief, given: given) == nil)
        #expect(Improver.checked(reply("add", "Name the project.", cites: []), brief: brief, given: given) == nil)
        #expect(Improver.checked(reply("remove", "Leave out breaks."), brief: brief, given: given) != nil)
        #expect(Improver.checked(reply("remove", "Leave out lunch."), brief: brief, given: given) == nil)
        #expect(Improver.checked(reply("remove", brief), brief: brief, given: given) == nil, "never empty the brief")
        #expect(Improver.checked(reply("add", String(repeating: "a", count: 401)), brief: brief, given: given) == nil)
        #expect(Improver.checked(reply("none", ""), brief: brief, given: given) == nil)
        #expect(Improver.checked(reply("add", "Two\nlines."), brief: brief, given: given) == nil)
    }
}

@Suite struct DecisionLogTests {
    @Test func decisionsAreAppendedNeverChangedAndReadNewestFirst() throws {
        let store = try makeStore()
        let trial = Decision(
            at: t0, task: "day.timeline", kind: .trial, by: .proposer, brief: "B", parentBrief: "A",
            detail: ["why": "breaks"])
        try store.log(trial)
        try store.log(Decision(at: t0, task: "day.timeline", kind: .promote, by: .person, brief: "B", parentBrief: "A"))
        try store.log(Decision(at: t0, task: "team.ledger", kind: .trial, by: .person, brief: "C", parentBrief: "D"))
        let decisions = try store.queries.decisions(of: "day.timeline")
        #expect(decisions.map(\.kind) == [.promote, .trial])
        #expect(decisions.last == trial)
        #expect(throws: (any Error).self) {
            try store.database.run(
                "INSERT INTO machine_decision(task, at, kind, decided_by, brief, parent_brief, detail) VALUES ('t', 'x', 'undo', 'person', '', '', '{}')"
            )
        }
    }
}
