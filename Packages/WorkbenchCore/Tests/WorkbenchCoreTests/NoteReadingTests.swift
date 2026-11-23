import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// A machine reads a note like any source: through the evidence store, with the line numbers a run records in its window.
/// A fact that cites a note line quotes the person's own words, and a deleted paragraph takes the quote with it.
@Suite struct NoteReadingTests {
    private let today = WorkDay(containing: t0)

    private func reply(cite: Int64, quote: String) -> String {
        let when =
            #"{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""}"#
        return
            #"{"items":[{"person":"Asha","project":"Bolt Pay","kind":"commitment","text":"Send the deck","when":\#(when),"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":\#(cite),"quote":"\#(quote)"}]}"#
    }

    private func evidence(of store: Store) throws -> EvidenceSet {
        let stored = try store.queries.currentLines(in: ["Bolt Pay"], from: day(-1), to: day(2))
        return EvidenceSet(
            lines: stored.map {
                Evidence(
                    id: $0.number, start: $0.time ?? t0, line: "me: \($0.text)", quotable: [$0.text], lineID: $0.lineID,
                    provenance: $0.provenance)
            }, context: ["members": ["Asha"]])
    }

    @Test func aFactFromANoteCitesThePersonsOwnWordsAndTheRunRecordsTheLine() async throws {
        let world = try NoteEvidenceTests.World()
        _ = try await world.note(["Intro", "I will send the deck to Meera by Friday"])
        let evidence = try evidence(of: world.store)
        let line = try #require(evidence.lines.last)
        let model = ScriptedModel(reply(cite: line.id, quote: "send the deck to Meera"))
        let result = try await HelperReader(spec: .team, model: RecordedModel(model, store: world.store))
            .read(day: today, scope: "team", evidence: evidence)
        #expect(result.dropped == 0 && result.items.count == 1)
        try world.store.saveReading(
            result, of: .team, day: today, scope: "team", grant: grant(.whatsapp, label: "team"))
        let fact = try #require(
            try world.store.queries.items(of: HelperSpec.team.task, day: today, scope: "team").first)
        #expect(fact.quote == "send the deck to Meera" && fact.authority == .ownWords)
        let windows = try world.store.queries.window(of: try #require(result.run))
        #expect(windows.map(\.text) == ["Intro", "I will send the deck to Meera by Friday"])
        #expect(windows.allSatisfy { $0.actor == "me" })
    }

    @Test func deletingTheParagraphEmptiesTheQuoteOfTheFactThatCitedIt() async throws {
        let world = try NoteEvidenceTests.World()
        var document = try await world.note(["Intro", "I will send the deck to Meera by Friday"])
        let evidence = try evidence(of: world.store)
        let line = try #require(evidence.lines.last)
        let result = try await HelperReader(
            spec: .team,
            model: RecordedModel(ScriptedModel(reply(cite: line.id, quote: "send the deck")), store: world.store)
        ).read(day: today, scope: "team", evidence: evidence)
        try world.store.saveReading(
            result, of: .team, day: today, scope: "team", grant: grant(.whatsapp, label: "team"))
        document.replace(6..<document.text.utf16.count, with: "")
        try await world.save(&document)
        let fact = try #require(
            try world.store.queries.items(of: HelperSpec.team.task, day: today, scope: "team").first)
        #expect(fact.quote == "" && fact.isSourceDeleted)
        let current = try world.store.queries.currentLines(in: ["Bolt Pay"], from: day(-1), to: day(2))
        #expect(current.filter { !$0.isTombstone }.map(\.text) == ["Intro"] && current.contains(where: \.isTombstone))
    }

    @Test func aMergeLeavesTheFactItsQuoteAndTheCitedLineAnswersWhereItWent() async throws {
        let world = try NoteEvidenceTests.World()
        var document = try await world.note(["Intro", "I will send the deck to Meera by Friday"])
        let evidence = try evidence(of: world.store)
        let line = try #require(evidence.lines.last)
        let result = try await HelperReader(
            spec: .team,
            model: RecordedModel(ScriptedModel(reply(cite: line.id, quote: "send the deck")), store: world.store)
        ).read(day: today, scope: "team", evidence: evidence)
        try world.store.saveReading(
            result, of: .team, day: today, scope: "team", grant: grant(.whatsapp, label: "team"))
        document.replace(5..<6, with: "")
        try await world.save(&document)
        let fact = try #require(
            try world.store.queries.items(of: HelperSpec.team.task, day: today, scope: "team").first)
        #expect(fact.quote == "send the deck" && !fact.isSourceDeleted)
        let proof = try world.store.queries.proofLines(of: fact, reach: 0)
        let move = try world.store.queries.paragraphMove(ofLine: try #require(proof.first).line.lineID)
        #expect(move?.note == NoteEvidenceTests.boltPay)
    }
}
