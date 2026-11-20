import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

private let first = WorkDay(containing: t0)
private let second = first.adding(days: 1)
private func at(_ day: WorkDay, _ minutes: Double) -> Date { day.start.addingTimeInterval(minutes * 60) }
private let chatGrant = grant(.whatsapp, label: "work")

private func fact(_ kind: String, _ text: String, cite: Int, quote: String) -> String {
    #"{"kind":"\#(kind)","text":"\#(text)","person":"Asha","project":"Deck","eta":"","asks":"team","stance":"said","cite":\#(cite),"quote":"\#(quote)"}"#
}

private func close(_ handle: String, _ outcome: String, cite: Int, quote: String) -> String {
    #"{"handle":"\#(handle)","outcome":"\#(outcome)","cite":\#(cite),"quote":"\#(quote)"}"#
}

/// Day one opens a commitment and a question; day two may close them.
private let dayOne = EvidenceSet(
    lines: [
        Evidence(
            id: 1, start: at(first, 600), line: "Asha: I will send the deck by Friday",
            quotable: ["I will send the deck by Friday"]),
        Evidence(
            id: 2, start: at(first, 610), line: "Raj: do we hire a designer?", quotable: ["do we hire a designer?"]),
    ], context: ["members": ["Asha", "Raj"]])

private let dayTwo = EvidenceSet(lines: [
    Evidence(id: 19, start: at(first, 500), line: "Asha: deck sent last month", quotable: ["deck sent last month"]),
    Evidence(id: 20, start: at(second, 600), line: "Asha: deck sent", quotable: ["deck sent"]),
    Evidence(id: 21, start: at(second, 620), line: "Raj: lunch?", quotable: ["lunch?"]),
])

@Suite struct WorkStateTests {
    private func openDayOne(_ store: Store) async throws {
        let reply =
            #"{"items":["# + fact("commitment", "Send the deck", cite: 1, quote: "send the deck")
            + "," + fact("question", "Hire a designer?", cite: 2, quote: "hire a designer?") + #"],"closes":[]}"#
        let reader = HelperReader(spec: .team, model: RecordedModel(ScriptedModel(reply), store: store))
        let result = try await reader.read(day: first, scope: "work", evidence: dayOne)
        try store.saveReading(result, of: .team, day: first, scope: "work", grant: chatGrant)
    }

    private func readDayTwo(
        _ store: Store, closes: [String], evidence: EvidenceSet = dayTwo
    ) async throws -> (HelperReader.Result, ScriptedModel) {
        let model = ScriptedModel(
            #"{"items":[],"closes":["# + closes.joined(separator: ",") + "]}")
        let reader = HelperReader(spec: .team, model: RecordedModel(model, store: store))
        let open = try store.queries.openItems(of: HelperSpec.team.task, lifecycle: HelperSpec.team.lifecycle!)
        return (try await reader.read(day: second, scope: "work", evidence: evidence, open: open), model)
    }

    @Test func theModelSeesOpenItemsByHandleAndAKeptPromiseCloses() async throws {
        let store = try makeStore()
        try await openDayOne(store)
        let (result, model) = try await readDayTwo(store, closes: [close("F1", "kept", cite: 20, quote: "deck sent")])
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(
            input.contains(
                "Still open from earlier days:\nF1 (\(first)) person=Asha project=Deck kind=commitment text=Send the deck"
            ))
        #expect(input.contains("F2 (\(first)) person=Asha project=Deck kind=question"))
        #expect(result.closes.count == 1 && result.dropped == 0)

        try store.saveReading(result, of: .team, day: second, scope: "work", grant: chatGrant, replacing: false)
        let open = try store.queries.openItems(of: HelperSpec.team.task, lifecycle: HelperSpec.team.lifecycle!)
        #expect(open.map { $0["kind"] } == ["question"])
        let closed = try store.queries.closedItems(of: HelperSpec.team.task, from: second.start, to: second.end)
        #expect(closed.map(\.closed) == [Item.Closed(outcome: "kept", quote: "deck sent", at: at(second, 600))])
        #expect(try store.queries.closedItems(of: HelperSpec.team.task, from: first.start, to: first.end).isEmpty)
    }

    @Test(arguments: [
        ("unknown handle", close("F9", "kept", cite: 20, quote: "deck sent")),
        ("no handle form", close("1", "kept", cite: 20, quote: "deck sent")),
        ("quote not in the line", close("F1", "kept", cite: 20, quote: "deck mailed")),
        ("line does not exist", close("F1", "kept", cite: 99, quote: "deck sent")),
        ("line older than the item", close("F1", "kept", cite: 19, quote: "deck sent last month")),
    ])
    func aCloseThatFailsACheckIsDropped(_ check: String, _ given: String) async throws {
        let store = try makeStore()
        try await openDayOne(store)
        let (result, _) = try await readDayTwo(store, closes: [given])
        #expect(result.closes.isEmpty, "\(check)")
        #expect(result.dropped == 1, "\(check)")
    }

    @Test func aLineReadBeforeCannotCloseAndOneItemClosesOnce() async throws {
        let store = try makeStore()
        try await openDayOne(store)
        let reread = EvidenceSet(lines: dayTwo.lines, readUpTo: 20)
        let (old, _) = try await readDayTwo(
            store, closes: [close("F1", "kept", cite: 20, quote: "deck sent")], evidence: reread)
        #expect(old.closes.isEmpty && old.dropped == 1)
        let (twice, _) = try await readDayTwo(
            store,
            closes: [
                close("F1", "kept", cite: 20, quote: "deck sent"), close("F1", "dropped", cite: 20, quote: "deck"),
            ]
        )
        #expect(twice.closes.map(\.outcome) == ["kept"] && twice.dropped == 1)
    }

    @Test func theFounderClosesAndReopensByHandAndARejectedItemIsNotOpen() async throws {
        let store = try makeStore()
        try await openDayOne(store)
        let lifecycle = HelperSpec.team.lifecycle!
        var open = try store.queries.openItems(of: HelperSpec.team.task, lifecycle: lifecycle)
        try store.close(item: try #require(open[0].id), as: "dropped")
        open = try store.queries.openItems(of: HelperSpec.team.task, lifecycle: lifecycle)
        #expect(open.map { $0["kind"] } == ["question"])
        let closed = try store.queries.items(of: HelperSpec.team.task, day: first, scope: "work")
            .first { $0["kind"] == "commitment" }
        #expect(closed?.closed?.outcome == "dropped" && closed?.closed?.quote == nil)

        try store.reopen(item: try #require(closed?.id))
        try store.mark(item: try #require(open[0].id), as: .rejected)
        open = try store.queries.openItems(of: HelperSpec.team.task, lifecycle: lifecycle)
        #expect(open.map { $0["kind"] } == ["commitment"])
    }

    @Test func openItemsAsOfADayHideWhatWasClosedBeforeItAndShowWhatWasClosedAfterIt() async throws {
        let now = Mutex(t0)
        let store = try makeStore(clock: { now.withLock { $0 } })
        try await openDayOne(store)
        let task = HelperSpec.team.task
        let lifecycle = HelperSpec.team.lifecycle!
        let items = try store.queries.items(of: task, day: first, scope: "work")
        let commitment = try #require(items.first { $0["kind"] == "commitment" }?.id)
        let question = try #require(items.first { $0["kind"] == "question" }?.id)
        func open(asOf day: WorkDay?) throws -> [String] {
            try store.queries.openItems(of: task, lifecycle: lifecycle, asOf: day).map { $0["kind"] }
        }

        now.withLock { $0 = at(first, 700) }
        try store.close(item: question, as: "answered")
        now.withLock { $0 = at(second, 700) }
        try store.close(item: commitment, as: "kept")

        #expect(try open(asOf: nil) == [])
        #expect(try open(asOf: second) == ["commitment"], "closed on the day: open as of its start; closed before: not")
        #expect(try open(asOf: first) == ["commitment", "question"], "both were closed after day one started")
        #expect(try open(asOf: first.adding(days: -1)) == [], "nothing was opened before that day ended")

        now.withLock { $0 = at(second, 800) }
        try store.reopen(item: question)
        #expect(try open(asOf: second) == ["commitment"], "a reopening after the day started does not count")
        #expect(try open(asOf: second.adding(days: 1)) == ["question"], "a reopening before it does")
    }

    @Test func onlyAMachineWithALifecycleIsToldAboutClosesOrSeesOpenItems() async throws {
        let store = try makeStore()
        let facts = HelperReader(spec: .team, model: RecordedModel(ScriptedModel("{}"), store: store))
        #expect(facts.instructions.contains("Close only when the line says so"))
        #expect(try facts.schema.jsonText.contains(#""closes""#))
        let pages = HelperReader(spec: .pages, model: RecordedModel(ScriptedModel("{}"), store: store))
        #expect(!pages.instructions.contains("Close only"))
        #expect(try !pages.schema.jsonText.contains(#""closes""#))
        #expect(HelperSpec.team.views["open by project"] == .checklist(by: "project"))
        #expect(HelperSpec.pages.views.values.allSatisfy { if case .checklist = $0 { false } else { true } })
    }

    @Test func aPlanOpenedYesterdayStaysOpenUntilTodaysLineClosesIt() async throws {
        let store = try makeStore()
        let plan = fact("plan", "Finish the login API", cite: 1, quote: "finish the login API")
        let opened = HelperReader(
            spec: .team, model: RecordedModel(ScriptedModel(#"{"items":["# + plan + #"],"closes":[]}"#), store: store))
        let yesterday = EvidenceSet(
            lines: [
                Evidence(
                    id: 1, start: at(first, 600), line: "Asha: I will finish the login API",
                    quotable: ["I will finish the login API"])
            ], context: ["members": ["Asha"]])
        let result = try await opened.read(day: first, scope: "work", evidence: yesterday)
        try store.saveReading(result, of: .team, day: first, scope: "work", grant: chatGrant)
        #expect(try store.queries.openItems(readBy: .team, asOf: second).map { $0["kind"] } == ["plan"])

        let today = EvidenceSet(
            lines: yesterday.lines + [
                Evidence(
                    id: 20, start: at(second, 600), line: "Asha: login API shipped", quotable: ["login API shipped"])
            ], context: ["members": ["Asha"]], readUpTo: 1)
        let (closing, _) = try await readDayTwo(
            store, closes: [close("F1", "kept", cite: 20, quote: "login API shipped")], evidence: today)
        try store.saveReading(closing, of: .team, day: second, scope: "work", grant: chatGrant, replacing: false)
        #expect(try store.queries.openItems(readBy: .team).isEmpty)
        let closed = try store.queries.closedItems(of: HelperSpec.team.task, from: second.start, to: second.end)
        #expect(closed.map { $0.closed?.outcome } == ["kept"] && closed.map { $0["kind"] } == ["plan"])
    }

    @Test func aDoneOrStatusFactIsNeverOpen() async throws {
        let store = try makeStore()
        let reply =
            #"{"items":["# + fact("done", "Login API shipped", cite: 1, quote: "login API shipped") + ","
            + fact("status", "Payments at 80 percent", cite: 2, quote: "payments at 80") + #"],"closes":[]}"#
        let evidence = EvidenceSet(
            lines: [
                Evidence(
                    id: 1, start: at(first, 600), line: "Asha: login API shipped", quotable: ["login API shipped"]),
                Evidence(id: 2, start: at(first, 610), line: "Asha: payments at 80", quotable: ["payments at 80"]),
            ], context: ["members": ["Asha"]])
        let result = try await HelperReader(spec: .team, model: RecordedModel(ScriptedModel(reply), store: store))
            .read(day: first, scope: "work", evidence: evidence)
        try store.saveReading(result, of: .team, day: first, scope: "work", grant: chatGrant)
        #expect(result.items.count == 2)
        #expect(try store.queries.openItems(readBy: .team).isEmpty)
    }
}
