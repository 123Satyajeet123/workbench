import Foundation
import Testing

@testable import WorkbenchCore

/// The lifecycle defects of research 59's audit (F-R1 probes p3, p4 and p5), each as a test that fails on the code
/// before this step and passes after it. Probes p1, p2 and p7 became tests in M2 step 1; p6 waits for the time
/// resolver (M2 step 4).
@Suite struct FactProbeTests {
    private let d2 = Days.second

    @Test func p3_aRestatedPromiseOnALaterDayIsOneOpenFactWithTwoCitations() async throws {
        let world = try LifecycleWorld()
        try await world.read(
            [pipItem(cite: 11, quote: "deck bhej dungi")],
            lines: [world.line(11, Days.first, 600, "kal tak deck bhej dungi")])
        try await world.read(
            [pipItem(cite: 20, quote: "pakka bhej dungi", relation: "same_as", handle: "F1")],
            lines: [world.line(20, d2, 600, "deck kal pakka bhej dungi")], day: d2)
        let open = try world.open()
        #expect(open.count == 1, "a restated promise is not a second fact")
        #expect(try world.kinds(of: try #require(open.first?.id)) == ["open", "restate"])
    }

    @Test func p4_aModelCloseOnOlderEvidenceNeverOverridesALaterPersonReopen() async throws {
        let world = try LifecycleWorld()
        world.clock.set(Days.at(Days.first, 700))
        try await world.read(
            [pipItem(cite: 11, quote: "deck bhej dungi")], lines: [world.line(11, Days.first, 600, "deck bhej dungi")])
        let id = try #require(world.open().first?.id)
        world.clock.set(Days.at(Days.first.adding(days: 3), 600))
        try world.store.close(item: id, as: "kept")
        world.clock.set(Days.at(Days.first.adding(days: 4), 600))
        try world.store.reopen(item: id)
        #expect(try world.open().count == 1)

        // Day 6: the founder opens day 2, which was never read, and reads it. The model closes the fact from a day-2
        // line, and then replaces it from another.
        world.clock.set(Days.at(Days.first.adding(days: 6), 600))
        try await world.read(
            [
                pipItem(
                    "done", "Deck sent", cite: 20, quote: "deck sent", relation: "closes", handle: "F1", outcome: "kept"
                )
            ],
            lines: [world.line(20, d2, 600, "deck sent"), world.line(21, d2, 610, "skip it")], day: d2, asOf: d2)
        try await world.read(
            [pipItem("decision", "Skip the deck", cite: 21, quote: "skip it", relation: "supersedes", handle: "F1")],
            lines: [world.line(20, d2, 600, "deck sent"), world.line(21, d2, 610, "skip it")], day: d2, asOf: d2,
            readUpTo: 20)
        #expect(try world.open().map(\.id).contains(id), "the person's reopen on day 5 stands")
        #expect(try world.all().first { $0.id == id }?.closed == nil)
    }

    @Test func p5_aHandledFindingOnAQuietMorningIsNotDeletedAndNotToldAgainAsNew() async throws {
        let world = try LifecycleWorld()
        world.clock.set(Days.at(d2, 300))
        let store = world.store
        let pip = try store.createMachine(from: .team, name: "Pip")
        let evidence = EvidenceSet(
            lines: [world.line(1, Days.first, 600, "I will send the deck by Friday")], context: LifecycleWorld.members)
        let pipReader = HelperReader(
            spec: pip.spec,
            model: RecordedModel(ScriptedModel(pipReply([pipItem(cite: 1, quote: "send the deck")])), store: store))
        let pipResult = try await pipReader.read(day: Days.first, scope: "work", evidence: evidence)
        try store.saveReading(
            pipResult, of: pip.spec, day: Days.first, scope: "work",
            grant: grant(.whatsapp, label: "work", at: world.clock.read()))
        var sentinel = HelperSpec.derailment
        sentinel.follows = pip.task
        let finding =
            #"{"items":[{"kind":"overdue","project":"Deck","severity":"act","next":"Ask Asha","reason":"Due, not sent","facts":["F1"],"lines":[],"quote":"send the deck"}]}"#
        func readSentinel(_ evidence: EvidenceSet) async throws {
            let reader = HelperReader(spec: sentinel, model: RecordedModel(ScriptedModel(finding), store: store))
            let result = try await reader.read(
                day: d2, scope: "work", evidence: evidence, open: try store.queries.openItems(readBy: sentinel))
            try store.saveReading(
                result, of: sentinel, day: d2, scope: "work",
                grant: grant(.whatsapp, label: "work", at: world.clock.read()))
        }
        try await readSentinel(EvidenceSet(lines: []))
        let first = try #require(store.queries.items(of: sentinel.task, on: d2).first)
        try store.apply(.done(outcome: "handled"), to: [try #require(first.id)])
        #expect(try store.queries.items(of: sentinel.task, on: d2).first?.closed != nil)

        world.clock.set(Days.at(d2, 360))
        try await readSentinel(EvidenceSet(lines: [world.line(5, d2, 350, "lunch?")]))
        let after = try store.queries.items(of: sentinel.task, on: d2)
        #expect(after.count == 1)
        #expect(after.first?.id == first.id, "the same row: no new id, so no new alert")
        #expect(after.first?.closed?.outcome == "handled", "the founder's close was not deleted")
    }
}
