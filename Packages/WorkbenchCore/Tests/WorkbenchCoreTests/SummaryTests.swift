import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

private let today = WorkDay(containing: t0)

/// Scope 1 is Asha (ids 1 and 2 on a fresh store), scope 2 is Raj (id 3): people sort by name.
private let reply = #"""
    {"summaries":[
    {"scope":1,"short":{"text":"Asha shipped the OTA and waits on a key.","cites":[1,2]},"details":[
    {"kind":"done","text":"Shipped the OTA.","cites":[1]},
    {"kind":"blocked","text":"Waits for the signing key.","cites":[2]}]},
    {"scope":2,"short":{"text":"Raj plans the hiring call.","cites":[3]},"details":[
    {"kind":"next","text":"Hiring call on Friday.","cites":[3]}]}]}
    """#

private struct Fixture {
    let store: Store
    let machine: Machine
    let model: ScriptedModel
    let summaries: Summaries

    init(reply: String = reply) throws {
        store = try makeStore()
        machine = try store.createMachine(from: .team, name: "Pip")
        model = ScriptedModel(reply)
        summaries = Summaries(store: store, model: RecordedModel(model, store: store))
    }

    var calls: Int { model.inputs.withLock { $0.count } }
    var lastInput: String { model.inputs.withLock { $0.last ?? "" } }

    var summaryRows: Int {
        (try? store.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM summary") }) ?? -1
    }

    /// Adds one item of `person`, found in `source`.
    func plant(_ person: String, _ text: String, in source: SourceKind = .whatsapp, line: Int64) throws {
        let run = try store.beginRun(task: "probe", model: "m", prompt: "p", input: text, kinds: [source])
        let item = Item(
            task: machine.task, day: today, scope: "work", source: source, citeFirst: line, citeLast: line,
            start: today.start.addingTimeInterval(Double(line) * 60),
            end: today.start.addingTimeInterval(Double(line) * 60),
            fields: ["person": person, "kind": "done", "text": text], quote: text, run: run)
        try store.saveReading(
            HelperReader.Result(items: [item], dropped: 0, run: nil), of: machine.spec, day: today, scope: "work",
            grant: grant(.whatsapp, label: "work"), replacing: false)
    }

    func plantTeam() throws {
        try plant("Asha", "OTA shipped", line: 1)
        try plant("Asha", "need the signing key", line: 2)
        try plant("Raj", "hiring call Friday", line: 3)
    }

    func ask() async throws -> [Summary] {
        try await summaries.summaries(for: today, groupedBy: "person", of: machine.task)
    }
}

@Suite struct SummarizerTests {
    private func scope(_ name: String, ids: [Int64]) -> SummaryScope {
        SummaryScope(
            name: name,
            sources: ids.map { id in
                CitedSource(
                    machine: "Pip", fields: ["person"],
                    item: Item(
                        id: id, task: "t", day: today, scope: "", source: .whatsapp, citeFirst: id, citeLast: id,
                        start: t0, end: t0, fields: ["person": name], quote: "q\(id)", run: 1))
            })
    }

    private func summarizer(_ reply: String) throws -> (Summarizer, ScriptedModel) {
        let model = ScriptedModel(reply)
        return (Summarizer(model: RecordedModel(model, store: try makeStore())), model)
    }

    @Test func aLineIsKeptOnlyWhenItCitesItemsOfItsOwnScope() async throws {
        let (summarizer, _) = try summarizer(
            #"""
            {"summaries":[{"scope":1,"short":{"text":"Asha is on it.","cites":[1]},"details":[
            {"kind":"done","text":"Own item.","cites":[1]},
            {"kind":"done","text":"Raj's item.","cites":[3]},
            {"kind":"next","text":"Mixed.","cites":[1,3]},
            {"kind":"blocked","text":"Nothing cited.","cites":[]},
            {"kind":"blocked","text":"Invented.","cites":[99]}]},
            {"scope":2,"short":{"text":"Raj, from Asha's item.","cites":[1]},"details":[]}]}
            """#)
        let summaries = try await summarizer.summarize(
            [scope("person: Asha", ids: [1, 2]), scope("person: Raj", ids: [3])], day: today)
        #expect(summaries[0].details.map(\.text) == ["Own item."])
        #expect(summaries[0].short?.cites == [1])
        #expect(summaries[1].short == nil, "a short line citing another scope's item is dropped")
    }

    @Test func aLineCitingNothingIsDropped() async throws {
        let (summarizer, _) = try summarizer(
            #"""
            {"summaries":[{"scope":1,"short":{"text":"Uncited.","cites":[]},"details":[
            {"kind":"done","text":"Uncited too.","cites":[]}]}]}
            """#)
        let summary = try #require(try await summarizer.summarize([scope("person: Asha", ids: [1])], day: today).first)
        #expect(summary.short == nil && summary.details.isEmpty)
    }

    @Test func aScopeWithNoItemsMakesNoCall() async throws {
        let (summarizer, model) = try summarizer(reply)
        #expect(try await summarizer.summarize([], day: today).isEmpty)
        #expect(try await summarizer.summarize([scope("person: Asha", ids: [])], day: today).isEmpty)
        #expect(model.inputs.withLock { $0.isEmpty })
    }

    @Test func manyScopesAreOneCallHoldingTheUnionOfTheirKinds() async throws {
        let store = try makeStore()
        let model = ScriptedModel(reply)
        let summarizer = Summarizer(model: RecordedModel(model, store: store))
        var screen = scope("person: Raj", ids: [3])
        screen.sources[0].item.source = .screen
        let summaries = try await summarizer.summarize([scope("person: Asha", ids: [1, 2]), screen], day: today)
        #expect(summaries.count == 2 && model.inputs.withLock { $0.count } == 1)
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("## [1] person: Asha") && input.contains("## [2] person: Raj"))
        let run = try #require(summaries.first?.run)
        #expect(try store.queries.runText(of: run)?.kinds == [.whatsapp, .screen])
    }

    @Test func aScopeNumberTheModelWasNotGivenOrAnsweredTwiceIsLeftOut() async throws {
        let line = #"{"text":"Ok.","cites":[1]}"#
        let (summarizer, _) = try summarizer(
            #"{"summaries":[{"scope":1,"short":\#(line),"details":[]},{"scope":1,"short":\#(line),"details":[]},{"scope":7,"short":\#(line),"details":[]}]}"#
        )
        #expect(try await summarizer.summarize([scope("person: Asha", ids: [1])], day: today).count == 1)
    }

    @Test func anAnswerBeyondTheSchemaIsRefused() async throws {
        let (summarizer, _) = try summarizer(
            #"{"summaries":[{"scope":1,"short":{"text":"Ok.","cites":[1]},"details":[{"kind":"later","text":"x","cites":[1]}]}]}"#
        )
        await #expect(throws: (any Error).self) {
            try await summarizer.summarize([scope("person: Asha", ids: [1])], day: today)
        }
    }
}

@Suite struct SummariesTests {
    @Test func aMachineIsGroupedByEachOfItsMemberAndLabelFields() {
        #expect(HelperSpec.team.summaryFields == ["person", "project"])
        var labelled = HelperSpec.team
        labelled.fields.removeAll { $0.name == "person" }
        #expect(labelled.summaryFields == ["project"])
        labelled.fields.removeAll { $0.name == "project" }
        #expect(labelled.summaryFields.isEmpty)
        #expect(HelperSpec.timeline.summaryFields.isEmpty)
    }

    @Test func aDayOfManyPeopleCostsOneCallAndEachSummaryIsKeptByScope() async throws {
        let fixture = try Fixture()
        try fixture.plantTeam()
        let summaries = try await fixture.ask()
        #expect(summaries.map(\.scope) == ["person: Asha", "person: Raj"] && fixture.calls == 1)
        #expect(summaries[0].short?.text == "Asha shipped the OTA and waits on a key.")
        #expect(fixture.summaryRows == 2)
    }

    @Test func aDayWithNoItemsMakesNoCall() async throws {
        let fixture = try Fixture()
        #expect(try await fixture.ask().isEmpty && fixture.calls == 0)
    }

    @Test func aWrongItemIsNotSentAndAnItemWithNoPersonBelongsToNoScope() async throws {
        let fixture = try Fixture()
        try fixture.plantTeam()
        try fixture.plant("", "someone did something", line: 4)
        try fixture.store.mark(item: 3, as: .rejected)
        _ = try await fixture.ask()
        let input = fixture.lastInput
        #expect(!input.contains("hiring call") && !input.contains("someone did something"))
        #expect(!input.contains("person: Raj"))
    }

    @Test func aSummaryIsReusedUntilItsItemsChangeThenOnlyThatScopeIsWrittenAgain() async throws {
        let fixture = try Fixture()
        try fixture.plantTeam()
        let first = try await fixture.ask()
        #expect(try await fixture.ask() == first && fixture.calls == 1, "opened again: no call")

        try fixture.plant("Asha", "key arrived", line: 4)
        _ = try await fixture.ask()
        #expect(fixture.calls == 2, "a new reading")
        #expect(fixture.lastInput.contains("key arrived") && !fixture.lastInput.contains("hiring call"))

        try fixture.store.mark(item: 1, as: .confirmed)
        _ = try await fixture.ask()
        #expect(fixture.calls == 3, "a mark")

        try fixture.store.close(item: 2, as: "kept")
        _ = try await fixture.ask()
        #expect(fixture.calls == 4, "a close")
        #expect(fixture.lastInput.contains("closed: kept"))

        _ = try await fixture.ask()
        #expect(fixture.calls == 4)
    }

    @Test func aDayIsMissingSummariesUntilTheyAreWrittenAndAgainWhenItsItemsChange() async throws {
        let fixture = try Fixture()
        let task = fixture.machine.task
        #expect(
            try !fixture.summaries.isMissing(for: today, groupedBy: "person", of: task), "no items, nothing missing")
        try fixture.plantTeam()
        #expect(try fixture.summaries.isMissing(for: today, groupedBy: "person", of: task))
        try await fixture.summaries.refresh(for: today, groupedBy: "person", of: task)
        #expect(try !fixture.summaries.isMissing(for: today, groupedBy: "person", of: task))
        try fixture.store.mark(item: 1, as: .confirmed)
        #expect(try fixture.summaries.isMissing(for: today, groupedBy: "person", of: task))
        #expect(fixture.calls == 1, "asking asks no model")
    }

    @Test func aSummaryIsKeptAcrossARestart() async throws {
        let fixture = try Fixture()
        try fixture.plantTeam()
        let first = try await fixture.ask()
        let again = Summaries(
            store: try fixture.store.reopened(), model: RecordedModel(fixture.model, store: fixture.store))
        #expect(try await again.summaries(for: today, groupedBy: "person", of: fixture.machine.task) == first)
        #expect(fixture.calls == 1)
    }

    @Test func refreshWritesWhatAPageThenReads() async throws {
        let fixture = try Fixture()
        try fixture.plantTeam()
        try await fixture.summaries.refresh(for: today, groupedBy: "person", of: fixture.machine.task)
        #expect(fixture.calls == 1 && fixture.summaryRows == 2)
        _ = try await fixture.ask()
        #expect(fixture.calls == 1)
    }

    @Test func aPrivacyDeleteOfASourceRemovesTheSummariesBuiltFromIt() async throws {
        let fixture = try Fixture()
        try fixture.plantTeam()
        _ = try await fixture.ask()
        try fixture.store.delete(.kind(.whatsapp, before: nil))
        #expect(fixture.summaryRows == 0)
    }

    @Test func aPrivacyDeleteOfScreenActivityRemovesSummariesBuiltFromScreenItems() async throws {
        let fixture = try Fixture()
        try fixture.plant("Asha", "OTA shipped", line: 1)
        try fixture.plant("Raj", "screen note", in: .screen, line: 2)
        _ = try await fixture.ask()
        try fixture.store.delete(.activities(ActivityFilter()))
        #expect(fixture.summaryRows == 1, "Asha's summary holds no screen text and stays")
    }

    @Test func aPrivacyDeleteOfAMachineRemovesItsSummariesAndTheSummaryRunText() async throws {
        let fixture = try Fixture()
        try fixture.plantTeam()
        let run = try #require(try await fixture.ask().first?.run)
        try fixture.store.delete(.machine(fixture.machine.task))
        #expect(fixture.summaryRows == 0)
        #expect(try fixture.store.queries.runText(of: run) == nil)
    }

    @Test func aSummaryBuiltFromADeletedItemIsRemovedAndTheScopeIsRebuiltWithoutIt() async throws {
        let fixture = try Fixture()
        try fixture.plant("Asha", "OTA shipped", line: 1)
        try fixture.plant("Asha", "secret screen detail", in: .screen, line: 2)
        try fixture.plant("Raj", "hiring call Friday", line: 3)
        _ = try await fixture.ask()
        try fixture.store.delete(.kind(.screen, before: nil))
        #expect(fixture.summaryRows == 1, "Raj's summary holds no screen text and stays; Asha's goes")

        let rebuilt = try await fixture.ask()
        #expect(fixture.calls == 2 && rebuilt.count == 2)
        #expect(!fixture.lastInput.contains("secret screen detail") && !fixture.lastInput.contains("hiring call"))
    }

    @Test func aScopeWhoseItemsAreAllGoneLeavesNoSummaryBehind() async throws {
        let fixture = try Fixture()
        try fixture.plant("Asha", "OTA shipped", line: 1)
        try fixture.plant("Raj", "hiring call Friday", line: 2)
        _ = try await fixture.ask()
        #expect(fixture.summaryRows == 2)
        try fixture.store.mark(item: 2, as: .rejected)
        #expect(try await fixture.ask().map(\.scope) == ["person: Asha"])
        #expect(fixture.summaryRows == 1, "Raj's kept text is removed, not just hidden")
    }
}
