import Foundation
import Testing

@testable import WorkbenchCore

private let first = WorkDay(containing: t0)
private let second = first.adding(days: 1)
private func at(_ day: WorkDay, _ minutes: Double) -> Date { day.start.addingTimeInterval(minutes * 60) }
private let chatGrant = grant(.whatsapp, label: "work")

private func fact(_ kind: String, _ text: String, cite: Int, quote: String) -> String {
    #"{"kind":"\#(kind)","text":"\#(text)","who":"Asha","topic":"Deck","due":"","stance":"said","cite":\#(cite),"quote":"\#(quote)"}"#
}

private func close(_ handle: String, _ outcome: String, cite: Int, quote: String) -> String {
    #"{"handle":"\#(handle)","outcome":"\#(outcome)","cite":\#(cite),"quote":"\#(quote)"}"#
}

/// Day one opens a commitment and a question; day two may close them.
private let dayOne = EvidenceSet(lines: [
    Evidence(
        id: 1, start: at(first, 600), line: "Asha: I will send the deck by Friday",
        quotable: ["I will send the deck by Friday"]),
    Evidence(id: 2, start: at(first, 610), line: "Raj: do we hire a designer?", quotable: ["do we hire a designer?"]),
])

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
        let reader = HelperReader(spec: .context, model: RecordedModel(ScriptedModel(reply), store: store))
        let result = try await reader.read(day: first, scope: "work", evidence: dayOne)
        try store.saveReading(result, of: .context, day: first, scope: "work", grant: chatGrant)
    }

    private func readDayTwo(
        _ store: Store, closes: [String], evidence: EvidenceSet = dayTwo, offSchema: Bool = false
    ) async throws -> (HelperReader.Result, ScriptedModel) {
        let model = ScriptedModel(
            #"{"items":[],"closes":["# + closes.joined(separator: ",") + "]}", offSchema: offSchema)
        let reader = HelperReader(spec: .context, model: RecordedModel(model, store: store))
        let open = try store.queries.openItems(of: HelperSpec.context.task, lifecycle: HelperSpec.context.lifecycle!)
        return (try await reader.read(day: second, scope: "work", evidence: evidence, open: open), model)
    }

    @Test func theModelSeesOpenItemsByHandleAndAKeptPromiseCloses() async throws {
        let store = try makeStore()
        try await openDayOne(store)
        let (result, model) = try await readDayTwo(store, closes: [close("F1", "kept", cite: 20, quote: "deck sent")])
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("Still open from earlier days:\nF1 (\(first)) kind=commitment text=Send the deck"))
        #expect(input.contains("F2 (\(first)) kind=question"))
        #expect(result.closes.count == 1 && result.dropped == 0)

        try store.saveReading(result, of: .context, day: second, scope: "work", grant: chatGrant, replacing: false)
        let open = try store.queries.openItems(of: HelperSpec.context.task, lifecycle: HelperSpec.context.lifecycle!)
        #expect(open.map { $0["kind"] } == ["question"])
        let closed = try store.queries.closedItems(of: HelperSpec.context.task, from: second.start, to: second.end)
        #expect(closed.map(\.closed) == [Item.Closed(outcome: "kept", quote: "deck sent", at: at(second, 600))])
        #expect(try store.queries.closedItems(of: HelperSpec.context.task, from: first.start, to: first.end).isEmpty)
    }

    @Test(arguments: [
        ("unknown handle", close("F9", "kept", cite: 20, quote: "deck sent")),
        ("no handle form", close("1", "kept", cite: 20, quote: "deck sent")),
        ("outcome not allowed", close("F1", "done", cite: 20, quote: "deck sent")),
        ("quote not in the line", close("F1", "kept", cite: 20, quote: "deck mailed")),
        ("line does not exist", close("F1", "kept", cite: 99, quote: "deck sent")),
        ("line older than the item", close("F1", "kept", cite: 19, quote: "deck sent last month")),
    ])
    func aCloseThatFailsACheckIsDropped(_ check: String, _ given: String) async throws {
        let store = try makeStore()
        try await openDayOne(store)
        let (result, _) = try await readDayTwo(store, closes: [given], offSchema: check == "outcome not allowed")
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
        let lifecycle = HelperSpec.context.lifecycle!
        var open = try store.queries.openItems(of: HelperSpec.context.task, lifecycle: lifecycle)
        try store.close(item: try #require(open[0].id), as: "dropped")
        open = try store.queries.openItems(of: HelperSpec.context.task, lifecycle: lifecycle)
        #expect(open.map { $0["kind"] } == ["question"])
        let closed = try store.queries.items(of: HelperSpec.context.task, day: first, scope: "work")
            .first { $0["kind"] == "commitment" }
        #expect(closed?.closed?.outcome == "dropped" && closed?.closed?.quote == nil)

        try store.reopen(item: try #require(closed?.id))
        try store.mark(item: try #require(open[0].id), as: .rejected)
        open = try store.queries.openItems(of: HelperSpec.context.task, lifecycle: lifecycle)
        #expect(open.map { $0["kind"] } == ["commitment"])
    }

    @Test func onlyAMachineWithALifecycleIsToldAboutClosesOrSeesOpenItems() async throws {
        let store = try makeStore()
        let context = HelperReader(spec: .context, model: RecordedModel(ScriptedModel("{}"), store: store))
        #expect(context.instructions.contains("Close only when the line says so"))
        #expect(try context.schema.jsonText.contains(#""closes""#))
        let team = HelperReader(spec: .team, model: RecordedModel(ScriptedModel("{}"), store: store))
        #expect(!team.instructions.contains("Close only"))
        #expect(try !team.schema.jsonText.contains(#""closes""#))
        #expect(HelperSpec.context.views["open by topic"] == .checklist(by: "topic"))
        #expect(HelperSpec.team.views.values.allSatisfy { if case .checklist = $0 { false } else { true } })
    }
}
