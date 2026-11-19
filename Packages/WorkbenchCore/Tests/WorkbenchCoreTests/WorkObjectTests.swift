import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct WorkObjectTests {
    private func event(
        _ id: String, _ kind: WorkEvent.Kind, by author: String, clock: Int, _ text: String = "",
        replaces: [String] = [], item: LinkedItem? = nil
    ) -> WorkEvent {
        WorkEvent(
            id: id, object: "deal-1", author: author, clock: clock, at: t0, kind: kind, text: text, replaces: replaces,
            item: item)
    }

    private var start: [WorkEvent] {
        [
            event("c", .create, by: "Asha", clock: 1, "deal"), event("t", .title, by: "Asha", clock: 2, "Acme"),
            event("s1", .stage, by: "Asha", clock: 3, "Screen"),
        ]
    }

    @Test func aMoveThatSawTheLastOneReplacesIt() throws {
        let events = start + [event("s2", .stage, by: "Kabir", clock: 4, "Diligence", replaces: ["s1"])]
        let deal = try #require(WorkObject.fold(events, viewer: "Kabir").first)
        #expect(deal.title == "Acme" && deal.stages == ["Diligence"] && deal.stageHeads == ["s2"])
    }

    @Test func twoMovesThatDidNotSeeEachOtherBothStandUntilOneMoveReplacesBoth() throws {
        var events =
            start + [
                event("s2", .stage, by: "Kabir", clock: 4, "Diligence", replaces: ["s1"]),
                event("s3", .stage, by: "Asha", clock: 4, "Passed", replaces: ["s1"]),
            ]
        var deal = try #require(WorkObject.fold(events, viewer: "Asha").first)
        #expect(deal.stages == ["Diligence", "Passed"], "a conflict is shown, never hidden")
        events.append(event("s4", .stage, by: "Asha", clock: 5, "Decision", replaces: deal.stageHeads))
        deal = try #require(WorkObject.fold(events, viewer: "Asha").first)
        #expect(deal.stages == ["Decision"])
    }

    @Test func theEarliestOpenClaimHoldsTheDealAndAReleaseHandsItOn() throws {
        var events =
            start + [
                event("k1", .claim, by: "Asha", clock: 4), event("k2", .claim, by: "Kabir", clock: 5),
            ]
        var deal = try #require(WorkObject.fold(events, viewer: "Asha").first)
        #expect(deal.holder == "Asha" && deal.alsoClaimed == ["Kabir"])
        events.append(event("r1", .release, by: "Asha", clock: 6))
        deal = try #require(WorkObject.fold(events, viewer: "Asha").first)
        #expect(deal.holder == "Kabir" && deal.alsoClaimed.isEmpty)
    }

    @Test func aLinkedItemShowsOnlyToPeopleInItsAudience() throws {
        let day = WorkDay(containing: t0)
        let item = Item(
            task: "vc.deals-1", day: day, scope: "", source: .screenText, citeFirst: 1, citeLast: 1, start: t0, end: t0,
            fields: ["company": "Acme"], quote: "Acme raises", run: 1)
        let machine = Machine(id: 1, name: "Deal intake", template: "vc.deals", spec: .dealIntake, state: .active)
        let linked = LinkedItem(machine: machine, item: item, audience: ["Asha"])
        let events = start + [event("l1", .link, by: "Asha", clock: 4, item: linked)]
        #expect(try #require(WorkObject.fold(events, viewer: "Asha").first).items.map(\.item.quote) == ["Acme raises"])
        #expect(try #require(WorkObject.fold(events, viewer: "Kabir").first).items.isEmpty)
        #expect(
            WorkObject.fold([event("l1", .link, by: "Asha", clock: 4, item: linked)], viewer: "Asha").isEmpty,
            "no object without its create event")
    }

    @Test func theSameEventImportedTwiceIsKeptOnceAndTheClockMovesPastEverythingSeen() throws {
        let store = try makeStore()
        #expect(try store.queries.nextClock() == 1)
        try store.append(start)
        try store.append(start + [event("s9", .stage, by: "Kabir", clock: 40, "Invested", replaces: ["s1"])])
        #expect(try store.queries.workEvents().count == 4)
        #expect(try store.queries.nextClock() == 41)
        #expect(
            try store.queries.workEvents() == start + [
                event("s9", .stage, by: "Kabir", clock: 40, "Invested", replaces: ["s1"])
            ])
    }
}
