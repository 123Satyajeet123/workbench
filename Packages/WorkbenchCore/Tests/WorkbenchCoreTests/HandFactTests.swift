import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// A fact the person adds by hand: no run, their own words, and the same item, marks and lifecycle as any fact.
@Suite struct HandFactTests {
    private let today = WorkDay(containing: t0)

    private func added(_ store: Store, _ fact: HandFact) throws -> Item {
        let id = try #require(try store.addFact(fact))
        return try #require(try store.queries.items(of: HelperSpec.team.task, on: today).first { $0.id == id })
    }

    @Test func aHandFactIsAnItemWithNoRunInThePersonsOwnWords() throws {
        let store = try makeStore()
        let item = try added(
            store, HandFact(kind: "commitment", text: "Send Meera the term sheet", person: "Asha", project: "Bolt Pay"))
        #expect(item.run == nil && item.source == .typed && item.authority == .ownWords)
        #expect(item.quote == "Send Meera the term sheet" && item.fields["text"] == "Send Meera the term sheet")
        #expect(item["person"] == "Asha" && item["project"] == "Bolt Pay" && item["kind"] == "commitment")
        #expect(item.state == .proposed && item.task == HelperSpec.team.task)
    }

    @Test func theOpeningEventRecordsThePersonAsTheActor() throws {
        let store = try makeStore()
        let item = try added(store, HandFact(kind: "plan", text: "Call the bank"))
        let actors = try store.writer.read {
            try Row.fetchAll(
                $0, sql: "SELECT actor, kind FROM item_event WHERE item_id = ?", arguments: [item.id]
            ).map { "\($0["kind"] as String):\($0["actor"] as String)" }
        }
        #expect(actors == ["open:person"])
    }

    @Test func aDueDayMakesItDueThatDayAndItIsOpenUntilClosed() throws {
        let store = try makeStore()
        let due = today.adding(days: 3)
        let item = try added(store, HandFact(kind: "commitment", text: "Sign the offer", due: due))
        #expect(item.due?.day == due && item.due?.source == .stated)
        let open = try store.queries.openItems(
            of: HelperSpec.team.task, lifecycle: try #require(HelperSpec.team.lifecycle))
        #expect(open.map(\.id) == [item.id])
        try store.close(item: try #require(item.id), as: "kept")
        #expect(
            try store.queries.openItems(of: HelperSpec.team.task, lifecycle: try #require(HelperSpec.team.lifecycle))
                .isEmpty)
    }

    @Test func aHandFactTakesTheSameMarksAsAnyFact() throws {
        let store = try makeStore()
        let item = try added(store, HandFact(kind: "decision", text: "Use the seed deck"))
        try store.mark(item: try #require(item.id), as: .confirmed)
        #expect(try store.queries.items(of: HelperSpec.team.task, on: today).first?.state == .confirmed)
    }

    @Test func theKindsComeFromTheMachineAndAKindItDoesNotHaveAddsNothing() throws {
        let store = try makeStore()
        #expect(
            HelperSpec.team.factKinds == ["plan", "done", "blocker", "commitment", "decision", "question", "status"])
        #expect(try store.addFact(HandFact(kind: "rumour", text: "Heard a thing")) == nil)
        #expect(try store.queries.items(of: HelperSpec.team.task, on: today).isEmpty)
    }

    @Test func emptyWordsAddNothing() throws {
        let store = try makeStore()
        #expect(try store.addFact(HandFact(kind: "plan", text: "   ")) == nil)
        #expect(try store.queries.items(of: HelperSpec.team.task, on: today).isEmpty)
    }

    @Test func aMachineWithNoKindsTakesNoHandFacts() throws {
        let store = try makeStore()
        #expect(HelperSpec.team.takesHandFacts && !HelperSpec.timeline.takesHandFacts)
        #expect(try store.addFact(HandFact(kind: "plan", text: "x"), to: .timeline) == nil)
    }

    @Test func theWordsKeepTheirSpellingInHindiAndEmoji() throws {
        let store = try makeStore()
        let item = try added(store, HandFact(kind: "plan", text: "कल डेक भेजना 👍", person: "आशा"))
        #expect(item.quote == "कल डेक भेजना 👍" && item["person"] == "आशा")
    }
}
