import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct BriefTests {
    private let day = WorkDay(containing: t0)

    private func source(_ id: Int64, _ text: String, _ state: Mark = .proposed) -> Briefer.Source {
        var item = Item(
            id: id, task: "team.ledger", day: day, scope: "", source: .whatsapp, citeFirst: id, citeLast: id,
            start: t0, end: t0, fields: ["person": "Asha", "kind": "blocker", "text": text], quote: text, run: 1)
        item.state = state
        return Briefer.Source(machine: "Pip", fields: ["person", "kind", "text"], item: item)
    }

    private func briefer(_ reply: String) throws -> (Briefer, ScriptedModel) {
        let scripted = ScriptedModel(reply)
        return (Briefer(model: RecordedModel(scripted, store: try makeStore())), scripted)
    }

    @Test func aLineIsKeptOnlyWhenItCitesItemsItWasGiven() async throws {
        let (briefer, scripted) = try briefer(
            #"""
            {"headline":"Asha is blocked on the OTA push.","lines":[
            {"kind":"stuck","basis":"seen","text":"Asha waits for the OTA push.","cites":[1]},
            {"kind":"next","basis":"inferred","text":"Ask Debayan to push the OTA.","cites":[1,2]},
            {"kind":"ask","basis":"seen","text":"Asha asks you to approve the push.","cites":[1]},
            {"kind":"happened","basis":"seen","text":"Made up.","cites":[99]},
            {"kind":"happened","basis":"seen","text":"Uncited.","cites":[]}]}
            """#)
        let brief = try #require(
            try await briefer.brief([source(1, "no OTA yet"), source(2, "flashed", .confirmed)], day: day))
        #expect(brief.lines.map(\.kind) == [.ask, .stuck, .next], "asks first")
        #expect(brief.lines.map(\.basis) == [.seen, .seen, .inferred])
        #expect(brief.headline == "Asha is blocked on the OTA push." && !brief.isQuiet)
        #expect(brief.dropped == 2 && brief.run != nil)
        let input = try #require(scripted.inputs.withLock { $0.first })
        #expect(input.contains(#"[1] Pip · person=Asha kind=blocker text=no OTA yet — "no OTA yet" — unmarked"#))
        #expect(input.contains("— right"))
    }

    @Test func aDayWithNoItemsMakesNoCallAndABriefHasAtMostEightLines() async throws {
        let (empty, scripted) = try briefer(#"{"headline":"","lines":[]}"#)
        #expect(try await empty.brief([], day: day) == nil)
        #expect(scripted.inputs.withLock { $0.isEmpty })
        let many = (0..<12).map { _ in #"{"kind":"happened","basis":"seen","text":"Done.","cites":[1]}"# }
            .joined(separator: ",")
        let (long, _) = try briefer("{\"headline\":\"Quiet day.\",\"lines\":[\(many)]}")
        let brief = try #require(try await long.brief([source(1, "done")], day: day, unseen: ["Timeline"]))
        #expect(brief.lines.count == Briefer.maximumLines)
        #expect(brief.isQuiet && brief.unseen == ["Timeline"], "nothing asked or stuck: a quiet day")
    }
}
