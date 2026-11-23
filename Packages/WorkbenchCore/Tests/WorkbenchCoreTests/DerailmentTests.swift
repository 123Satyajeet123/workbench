import Foundation
import Testing

@testable import WorkbenchCore

private let first = WorkDay(containing: t0)
private let second = first.adding(days: 1)
private func at(_ day: WorkDay, _ minutes: Double) -> Date { day.start.addingTimeInterval(minutes * 60) }
private let chatGrant = grant(.whatsapp, label: "work")

private let dayOne = EvidenceSet(
    lines: [
        Evidence(
            id: 1, start: at(first, 600), line: "Asha: I will send the deck by Friday",
            quotable: ["I will send the deck by Friday"]),
        Evidence(
            id: 2, start: at(first, 610), line: "Raj: do we hire a designer?", quotable: ["do we hire a designer?"]),
    ], context: ["members": ["Asha", "Raj"]])

private let dayTwo = EvidenceSet(
    lines: [
        Evidence(id: 20, start: at(second, 500), line: "Asha: pitch is on", quotable: ["pitch is on"]),
        Evidence(
            id: 21, start: at(second, 600), line: "Raj: still waiting on the deck",
            quotable: ["still waiting on the deck"]),
        Evidence(id: 22, start: at(second, 620), line: "Raj: lunch?", quotable: ["lunch?"]),
    ], readUpTo: 20)

private func finding(
    kind: String = "overdue", facts: String = #"["F1"]"#, lines: String = "[21]", quote: String = "waiting on the deck"
) -> String {
    #"{"kind":"\#(kind)","project":"Deck","severity":"act","next":"Ask Asha for the deck","reason":"Due Friday, not sent","facts":\#(facts),"lines":\#(lines),"quote":"\#(quote)"}"#
}

private func reply(_ findings: String...) -> String { #"{"items":["# + findings.joined(separator: ",") + "]}" }

@Suite struct DerailmentTests {
    private func watch() async throws -> (store: Store, sentinel: HelperSpec) {
        let store = try makeStore()
        let pip = try store.createMachine(from: .team, name: "Pip")
        let factsReply =
            #"{"items":[{"kind":"commitment","text":"Send the deck","person":"Asha","project":"Deck","eta":"Fri 25 Sep","asks":"team","stance":"said","cite":1,"quote":"send the deck"},{"kind":"question","text":"Hire a designer?","person":"Raj","project":"Team","eta":"","asks":"team","stance":"said","cite":2,"quote":"hire a designer?"}],"closes":[]}"#
        let reader = HelperReader(spec: pip.spec, model: RecordedModel(ScriptedModel(factsReply), store: store))
        let result = try await reader.read(day: first, scope: "work", evidence: dayOne)
        try store.saveReading(result, of: pip.spec, day: first, scope: "work", grant: chatGrant)
        var sentinel = HelperSpec.derailment
        sentinel.follows = pip.task
        return (store, sentinel)
    }

    private func read(
        _ store: Store, _ spec: HelperSpec, _ answer: String, day: WorkDay = second, evidence: EvidenceSet = dayTwo
    ) async throws -> (HelperReader.Result, ScriptedModel) {
        let model = ScriptedModel(answer)
        let reader = HelperReader(spec: spec, model: RecordedModel(model, store: store))
        let open = try store.queries.openItems(readBy: spec)
        return (try await reader.read(day: day, scope: "work", evidence: evidence, open: open), model)
    }

    @Test func theModelSeesTheFollowedMachinesOpenFactsAndAGoodFindingIsKeptWithTheirStoreIds() async throws {
        let (store, sentinel) = try await watch()
        let (result, model) = try await read(store, sentinel, reply(finding()))
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("Still open from earlier days:\nF1 (\(first)) asks=team eta=Fri 25 Sep kind=commitment"))
        #expect(input.contains(#"person=Asha project=Deck stance=said text=Send the deck — "send the deck""#))
        #expect(input.contains("F2 (\(first)) asks=team eta= kind=question"))
        #expect(result.items.count == 1 && result.dropped == 0)

        try store.saveReading(result, of: sentinel, day: second, scope: "work", grant: chatGrant, replacing: false)
        let saved = try #require(store.queries.items(of: sentinel.task, day: second, scope: "work").first)
        let followed = try store.queries.openItems(readBy: sentinel)
        #expect(saved["facts"] == "\(try #require(followed[0].id))")
        #expect(saved.citeFirst == 21 && saved.citeLast == 21 && saved.start == at(second, 600))
        #expect(saved["kind"] == "overdue" && saved["severity"] == "act" && saved.quote == "waiting on the deck")
    }

    @Test func aFollowerAlsoWatchesEveryMachineThatKeepsTheSameKindOfFacts() async throws {
        let (store, sentinel) = try await watch()
        let relay = try store.createMachine(from: .teamTelegram, name: "Relay")
        let timeline = try store.createMachine(from: .timeline, name: "Timeline")
        let reply =
            #"{"items":[{"kind":"blocker","text":"Waiting on the API keys","person":"Raj","project":"Payments","eta":"","asks":"founder","stance":"said","cite":1,"quote":"send the deck"}],"closes":[]}"#
        let reader = HelperReader(spec: relay.spec, model: RecordedModel(ScriptedModel(reply), store: store))
        let result = try await reader.read(day: first, scope: "group", evidence: dayOne)
        try store.saveReading(
            result, of: relay.spec, day: first, scope: "group", grant: grant(.telegram, label: "group"))
        let followed = try store.queries.openItems(readBy: sentinel)
        #expect(Set(followed.map(\.task)) == [sentinel.follows, relay.task])
        #expect(followed.contains { $0["project"] == "Payments" } && !followed.contains { $0.task == timeline.task })
    }

    @Test func aFindingOfSeveralFactsKeepsTheirIdsSortedAndOnceEach() async throws {
        let (store, sentinel) = try await watch()
        let (result, _) = try await read(store, sentinel, reply(finding(facts: #"["F2","F1","F2"]"#)))
        let ids = try store.queries.openItems(readBy: sentinel).compactMap(\.id).sorted()
        #expect(result.items.first?["facts"] == ids.map(String.init).joined(separator: ","))
    }

    @Test func aFindingThatRestsOnSilenceNeedsNoLineAndIsStoredWithNoSpan() async throws {
        let (store, sentinel) = try await watch()
        let silent = finding(lines: "[]", quote: "send the deck")
        let (result, _) = try await read(store, sentinel, reply(silent))
        #expect(result.items.count == 1)
        let item = try #require(result.items.first)
        #expect(item.citeFirst == 0 && item.citeLast == 0 && item.start == at(second, 620) && item.end == item.start)
        try store.saveReading(result, of: sentinel, day: second, scope: "work", grant: chatGrant, replacing: false)
        #expect(try store.queries.items(of: sentinel.task, day: second, scope: "work").count == 1)
    }

    @Test(arguments: [
        ("unknown handle", finding(facts: #"["F9"]"#)),
        ("no handle form", finding(facts: #"["1"]"#)),
        ("one handle unknown among known", finding(facts: #"["F1","F9"]"#)),
        ("no facts", finding(facts: "[]")),
        ("a line read before", finding(lines: "[20]", quote: "pitch is on")),
        ("a line that does not exist", finding(lines: "[99]")),
        ("a good line beside a missing one", finding(lines: "[21,99]")),
        ("a quote in neither a fact nor a line", finding(quote: "the deck is late")),
        ("a quote only in an uncited line", finding(lines: "[21]", quote: "lunch?")),
        ("a quote only in an uncited fact", finding(facts: #"["F2"]"#, lines: "[]", quote: "send the deck")),
    ])
    func aFindingThatFailsACheckIsDropped(_ check: String, _ given: String) async throws {
        let (store, sentinel) = try await watch()
        let (result, _) = try await read(store, sentinel, reply(given))
        #expect(result.items.isEmpty, "\(check)")
        #expect(result.dropped == 1, "\(check)")
    }

    @Test func aFindingToldTwiceInOneReplyIsKeptOnce() async throws {
        let (store, sentinel) = try await watch()
        let (result, _) = try await read(store, sentinel, reply(finding(), finding(lines: "[22]", quote: "lunch?")))
        #expect(result.items.count == 1 && result.dropped == 1)
    }

    @Test func aFindingToldInTheLastFourteenDaysIsNotAddedAgainButAnotherFactOrKindIs() async throws {
        let (store, sentinel) = try await watch()
        let (one, _) = try await read(store, sentinel, reply(finding()))
        try store.saveReading(one, of: sentinel, day: second, scope: "work", grant: chatGrant, replacing: false)

        let nextDay = second.adding(days: 1)
        let later = EvidenceSet(
            lines: [
                Evidence(id: 30, start: at(nextDay, 600), line: "Raj: ping on the deck", quotable: ["ping on the deck"])
            ])
        func save(_ answer: String, on day: WorkDay = nextDay) async throws -> Int {
            let (result, _) = try await read(store, sentinel, answer, day: day, evidence: later)
            try store.saveReading(result, of: sentinel, day: day, scope: "work", grant: chatGrant, replacing: false)
            return try store.queries.items(of: sentinel.task, since: first).count
        }
        let again = finding(lines: "[30]", quote: "ping on the deck")
        #expect(try await save(reply(again)) == 1, "the same finding the next day is not added")
        #expect(try await save(reply(finding(kind: "blocked", lines: "[30]", quote: "ping on the deck"))) == 2)
        #expect(try await save(reply(finding(facts: #"["F2"]"#, lines: "[30]", quote: "ping on the deck"))) == 3)
        #expect(try await save(reply(again), on: second.adding(days: 14)) == 3, "still told on day 14")
        #expect(try await save(reply(again), on: second.adding(days: 15)) == 4, "told again after 14 days")
    }

    @Test func aFindingRepeatsOneWithTheSameFactsAndTheSameValueInEveryChoiceFieldWhateverTheyAreCalled() async throws {
        var spec = HelperSpec.derailment
        spec.fields = spec.fields.map { field in
            var field = field
            if field.name == "kind" { field.name = "category" }
            return field
        }
        #expect(spec.choiceFields == ["category", "severity"])
        func finding(_ category: String, severity: String = "act", facts: String = "7") -> Item {
            Item(
                task: spec.task, day: second, scope: "work", source: .whatsapp, citeFirst: 0, citeLast: 0, start: t0,
                end: t0,
                fields: ["category": category, "severity": severity, "project": "Deck", "facts": facts],
                quote: "q", run: 1)
        }
        let told = finding("overdue")
        #expect(finding("overdue").repeats(told, citation: .facts, choices: spec.choiceFields))
        #expect(!finding("blocked").repeats(told, citation: .facts, choices: spec.choiceFields), "another category")
        #expect(!finding("overdue", severity: "info").repeats(told, citation: .facts, choices: spec.choiceFields))
        #expect(!finding("overdue", facts: "7,8").repeats(told, citation: .facts, choices: spec.choiceFields))
        #expect(
            finding("overdue", severity: "info").repeats(told, citation: .facts, choices: []),
            "with no choice fields only the facts count")

        let (store, _) = try await watch()
        func saved(_ item: Item) throws -> Int {
            let result = HelperReader.Result(items: [item], dropped: 0, run: nil)
            try store.saveReading(result, of: spec, day: second, scope: "work", grant: chatGrant, replacing: false)
            return try store.queries.items(of: spec.task, since: first).count
        }
        #expect(try saved(finding("overdue")) == 1)
        #expect(try saved(finding("overdue")) == 1, "told before: not added again")
        #expect(try saved(finding("blocked")) == 2)
    }

    @Test func aFollowedMachinesOpenItemsAreGivenAsOfTheDayRead() async throws {
        let (store, sentinel) = try await watch()
        let commitment = try #require(
            try store.queries.openItems(readBy: sentinel).first { $0["kind"] == "commitment" })
        try store.close(item: try #require(commitment.id), as: "kept")
        #expect(try store.queries.openItems(readBy: sentinel, asOf: first).count == 2, "closed after day one started")
        #expect(try store.queries.openItems(readBy: sentinel, asOf: second).count == 1, "closed before day two")
        #expect(try store.queries.openItems(readBy: sentinel).count == 1)
    }

    private let quietDay = EvidenceSet(lines: [])

    @Test func aDayWithNoLinesStillRunsTheMachineThatFollowsWhileFactsAreOpenAndKeepsAFindingOnSilence() async throws {
        let (store, sentinel) = try await watch()
        let silent = finding(lines: "[]", quote: "send the deck")
        let (result, model) = try await read(store, sentinel, reply(silent), day: second, evidence: quietDay)
        #expect(model.inputs.withLock { $0.count } == 1)
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("Work day: \(second)") && input.contains("F1 (\(first)) asks=team eta=Fri 25 Sep"))
        let item = try #require(result.items.first)
        #expect(result.items.count == 1 && result.run != nil)
        #expect(item.start == second.start && item.end == second.start && item.citeFirst == 0)
        try store.saveReading(result, of: sentinel, day: second, scope: "work", grant: chatGrant, replacing: false)
        #expect(try store.queries.items(of: sentinel.task, day: second, scope: "work").count == 1)
    }

    @Test func aDayWithNoLinesRunsNoModelWhenNothingIsOpenOrTheMachineFollowsNothing() async throws {
        let (store, sentinel) = try await watch()
        let model = ScriptedModel(reply())
        let none = try await HelperReader(spec: sentinel, model: RecordedModel(model, store: store))
            .read(day: second, scope: "work", evidence: quietDay, open: [])
        #expect(none.run == nil && model.inputs.withLock { $0.count } == 0, "no lines and no open facts")

        let team = ScriptedModel(reply())
        let open = try store.queries.openItems(readBy: sentinel)
        let teamResult = try await HelperReader(spec: .pages, model: RecordedModel(team, store: store))
            .read(day: second, scope: "work", evidence: quietDay, open: open)
        #expect(
            teamResult.run == nil && team.inputs.withLock { $0.count } == 0,
            "a machine that follows nothing stays quiet")
    }

    @Test func aMachineWithNoFollowsOrLifecycleIsNotShownOpenItemsAndKeepsItsRules() async throws {
        let store = try makeStore()
        let team = HelperReader(spec: .pages, model: RecordedModel(ScriptedModel("{}"), store: store))
        #expect(team.instructions.contains("Return no item"))
        #expect(!team.instructions.contains("another machine's record"))
        #expect(HelperReader.open([], spec: .pages) == "")

        let model = ScriptedModel(#"{"items":[]}"#)
        let reader = HelperReader(spec: .pages, model: RecordedModel(model, store: store))
        let (store2, sentinel) = try await watch()
        let open = try store2.queries.openItems(readBy: sentinel)
        _ = try await reader.read(day: second, scope: "work", evidence: dayTwo, open: open)
        #expect(try #require(model.inputs.withLock { $0.first }).contains("Still open") == false)
        #expect(try store2.queries.openItems(readBy: .pages).isEmpty)
    }

    @Test func aMachineThatFollowsNothingThatExistsSeesNothing() throws {
        let store = try makeStore()
        var sentinel = HelperSpec.derailment
        #expect(try store.queries.openItems(readBy: sentinel).isEmpty)
        sentinel.follows = "work.context-gone"
        #expect(try store.queries.openItems(readBy: sentinel).isEmpty)
    }

    @Test func theSchemaHoldsTheModelToIntegersAndArraysWithEveryPropertyRequired() throws {
        let store = try makeStore()
        let sentinel = HelperReader(spec: .derailment, model: RecordedModel(ScriptedModel("{}"), store: store))
        let text = try sentinel.schema.jsonText
        #expect(text.contains(#""facts":{"items":{"type":"string"},"type":"array"}"#))
        #expect(text.contains(#""lines":{"items":{"type":"integer"},"type":"array"}"#))
        #expect(text.contains(#""required":["kind","project","severity","next","reason","facts","lines","quote"]"#))
        #expect(sentinel.schema.accepts(json: reply(finding())))
        #expect(!sentinel.schema.accepts(json: reply(finding(facts: #""F1""#))))
        #expect(!sentinel.schema.accepts(json: reply(finding(lines: #"["21"]"#))))
        #expect(!sentinel.schema.accepts(json: reply(finding(lines: "[21.5]"))))
        #expect(!sentinel.schema.accepts(json: #"{"items":[{"kind":"overdue"}]}"#))
        #expect(!text.contains(#""closes""#))
    }

    @Test func theSentinelSpecIsAnOffTrackWatchWhoseOnlyBadToneIsAct() {
        let spec = HelperSpec.derailment
        #expect(spec.citation == .facts && spec.lifecycle == nil && spec.follows == nil && spec.needsFollowed)
        #expect(spec.tones == ["act": .bad, "watch": .attention, "info": .neutral])
        #expect(spec.view == .grouped(by: "severity"))
        #expect(spec.views["by severity"] == .grouped(by: "severity"))
        #expect(!HelperSpec.team.needsFollowed)
    }
}
