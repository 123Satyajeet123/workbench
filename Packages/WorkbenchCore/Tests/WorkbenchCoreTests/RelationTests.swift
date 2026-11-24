import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// The model says how each item relates to the open facts it was shown; code checks every handle and writes the
/// events. A commitment is its owner and its deliverable: a changed date is a change of date, not a new fact.
@Suite struct RelationTests {
    /// Day one opens a commitment of Asha (F1) and one of Raj (F2).
    private func worldWithTwoFacts() async throws -> LifecycleWorld {
        let world = try LifecycleWorld()
        try await world.read(
            [
                pipItem(when: TimeJSON.inDays(4, words: "Friday"), cite: 1, quote: "send the deck"),
                pipItem("commitment", "Fix the login", person: "Raj", cite: 2, quote: "fix the login"),
            ],
            lines: [
                world.line(1, Days.first, 600, "I will send the deck by Friday"),
                world.line(2, Days.first, 610, "I will fix the login"),
            ])
        return world
    }

    @discardableResult
    private func readDayTwo(
        _ world: LifecycleWorld, _ items: [String], extra: [Evidence] = []
    ) async throws -> HelperReader.Result {
        try await world.read(
            items, lines: [world.line(20, Days.second, 600, "deck kal pakka bhej dungi")] + extra,
            day: Days.second)
    }

    private func factID(_ world: LifecycleWorld, person: String) throws -> Int64 {
        try #require(world.open().first { $0["person"] == person }?.id)
    }

    // MARK: same_as

    @Test func sameAsAddsACitationToTheOldFactAndMakesNoNewFact() async throws {
        let world = try await worldWithTwoFacts()
        let result = try await readDayTwo(
            world, [pipItem(cite: 20, quote: "pakka bhej dungi", relation: "same_as", handle: "F1")])
        #expect(result.items.isEmpty && result.dropped == 0 && result.kept == 1)
        #expect(result.links.map(\.effect) == [.restate])
        #expect(try world.open().count == 2)
        let asha = try factID(world, person: "Asha")
        #expect(try world.kinds(of: asha) == ["open", "restate"])
        let restate = try world.db {
            try Row.fetchOne(
                $0, sql: "SELECT line_id, quote, actor, run_id FROM item_event WHERE kind = 'restate'")
        }
        #expect(restate?["line_id"] as Int64? == 20 && restate?["quote"] as String? == "pakka bhej dungi")
        #expect(restate?["actor"] as String? == "model" && (restate?["run_id"] as Int64?) != nil)
    }

    @Test func aChangedDateIsADueChangedEventAndNotANewFact() async throws {
        let world = try await worldWithTwoFacts()
        try await readDayTwo(
            world,
            [
                pipItem(
                    when: TimeJSON.inDays(8, words: "kal"), cite: 20, quote: "pakka bhej dungi", relation: "same_as",
                    handle: "F1")
            ])
        let asha = try #require(try world.open().first { $0["person"] == "Asha" })
        #expect(try world.open().count == 2, "no third fact")
        #expect(try world.kinds(of: try #require(asha.id)) == ["open", "restate", "due_changed"])
        #expect(asha["when"] == "Friday", "the opening row is never rewritten")
        #expect(asha.openedDue?.day == Days.first.adding(days: 4))
        #expect(asha.dueChanged?.day == Days.first.adding(days: 9) && asha.dueDay == Days.first.adding(days: 9))
        #expect(asha.dueChanged?.source == .resolved && asha.dueChanged?.record?.offsetDays == 8)
    }

    @Test func theSameDateOrNoDateWritesNoDueChange() async throws {
        let world = try await worldWithTwoFacts()
        try await readDayTwo(
            world,
            [
                pipItem(
                    when: TimeJSON.inDays(3, words: "kal"), cite: 20, quote: "pakka bhej dungi", relation: "same_as",
                    handle: "F1")
            ])
        try await world.read(
            [pipItem(cite: 21, quote: "kal bhej dungi", relation: "same_as", handle: "F1")],
            lines: [world.line(21, Days.second, 700, "kal bhej dungi")], day: Days.second, readUpTo: 20)
        let asha = try factID(world, person: "Asha")
        #expect(try world.kinds(of: asha) == ["open", "restate", "restate"])
    }

    @Test func theModelSeesTheLatestDateOfAFactItWasGiven() async throws {
        let world = try await worldWithTwoFacts()
        try await readDayTwo(
            world,
            [
                pipItem(
                    when: TimeJSON.inDays(8, words: "kal"), cite: 20, quote: "pakka bhej dungi", relation: "same_as",
                    handle: "F1")
            ])
        let open = try world.store.queries.openItems(readBy: .team)
        #expect(HelperReader.open(open.items, spec: .team).contains("due=\(Days.first.adding(days: 9))"))
        #expect(!HelperReader.open(open.items, spec: .team).contains("due=\(Days.first.adding(days: 4))"))
    }

    @Test func aSameAsWithAnotherOwnerIsDroppedAndTheSameOwnerPasses() async throws {
        let world = try await worldWithTwoFacts()
        let other = try await readDayTwo(
            world, [pipItem(person: "Raj", cite: 20, quote: "pakka bhej dungi", relation: "same_as", handle: "F1")])
        #expect(other.links.isEmpty && other.items.isEmpty && other.dropped == 1)
        #expect(try world.store.queries.dropReasons(of: try #require(other.run)).map(\.rule) == [.identityMismatch])
        let same = try await world.read(
            [pipItem(person: "Asha", cite: 21, quote: "bhej dungi", relation: "same_as", handle: "F1")],
            lines: [world.line(21, Days.second, 700, "bhej dungi")], day: Days.second, readUpTo: 20)
        #expect(same.links.map(\.effect) == [.restate] && same.dropped == 0)
    }

    // MARK: handles

    @Test(arguments: [
        ("a handle that was never shown", "same_as", "F9", ""),
        ("a handle with no F", "same_as", "1", ""),
        ("a supersedes with an unknown handle", "supersedes", "F3", ""),
        ("a closes with an unknown handle", "closes", "F0", "kept"),
        ("a same_as with no handle", "same_as", "", ""),
        ("a new that names a handle", "new", "F1", ""),
        ("an unsure that names a handle", "unsure", "F1", ""),
        ("a same_as that names an outcome", "same_as", "F1", "kept"),
        ("a closes with no outcome", "closes", "F1", ""),
    ])
    func aHandleOrRelationOutsideTheShownOpenSetIsRefusedWithADropRow(
        _ why: String, _ kind: String, _ handle: String, _ outcome: String
    ) async throws {
        let world = try await worldWithTwoFacts()
        let result = try await readDayTwo(
            world, [pipItem(cite: 20, quote: "pakka bhej dungi", relation: kind, handle: handle, outcome: outcome)])
        #expect(result.items.isEmpty && result.links.isEmpty && result.dropped == 1, "\(why)")
        let drops = try world.store.queries.dropReasons(of: try #require(result.run))
        #expect(drops.count == 1 && drops[0].part == "items", "\(why)")
        #expect(try world.kinds(of: try factID(world, person: "Asha")) == ["open"], "\(why): no event written")
    }

    @Test func codeRefusesAnOutcomeTheLifecycleLacksEvenWhenTheSchemaWouldHaveStoppedIt() throws {
        let item = Item(
            task: "t", day: Days.first, scope: "", source: .whatsapp, citeFirst: 1, citeLast: 1,
            start: Days.at(Days.second, 600), end: Days.at(Days.second, 600), fields: ["person": "Asha"], quote: "q",
            run: 1)
        let fact = Item(
            id: 7, task: "t", day: Days.first, scope: "", source: .whatsapp, citeFirst: 1, citeLast: 1,
            start: Days.at(Days.first, 600), end: Days.at(Days.first, 600), fields: ["person": "Asha"], quote: "q",
            run: 1)
        let verifier = Verifier(window: EvidenceSet(lines: []))
        func rule(_ outcome: String) throws -> DropRule? {
            let raw = try JSONDecoder().decode(
                [String: JSONValue].self,
                from: Data(#"{"relation":{"kind":"closes","handle":"F1","outcome":"\#(outcome)"}}"#.utf8))
            guard
                case .dropped(let rule) = verifier.verdict({
                    try verifier.relation(raw, spec: .team, open: [fact], item: item)
                })
            else { return nil }
            return rule
        }
        #expect(try rule("vanished") == .fieldKind)
        #expect(try rule("kept") == nil)
    }

    @Test func aHandleNamingAnOpenFactTheModelWasNotShownIsRefused() async throws {
        let world = try await worldWithTwoFacts()
        let raj = try world.open().first { $0["person"] == "Raj" }
        let shown = try world.open().filter { $0.id != raj?.id }
        let reader = HelperReader(
            spec: .team,
            model: RecordedModel(
                ScriptedModel(
                    pipReply([pipItem(cite: 20, quote: "pakka", relation: "closes", handle: "F2", outcome: "kept")])),
                store: world.store))
        let evidence = EvidenceSet(
            lines: [world.line(20, Days.second, 600, "pakka")], context: LifecycleWorld.members)
        let result = try await reader.read(day: Days.second, scope: "work", evidence: evidence, open: Capped(shown))
        #expect(
            shown.count == 1 && result.links.isEmpty && result.dropped == 1, "F2 was in the store, not in the shown set"
        )
    }

    @Test func aValidHandleIsAcceptedForEveryRelationThatNeedsOne() async throws {
        let world = try await worldWithTwoFacts()
        let result = try await readDayTwo(
            world,
            [
                pipItem(cite: 20, quote: "deck", relation: "same_as", handle: "F1"),
                pipItem(
                    "decision", "Skip the deck", person: "Raj", cite: 20, quote: "kal", relation: "supersedes",
                    handle: "F2"),
            ])
        #expect(result.dropped == 0 && result.items.count == 1 && result.links.count == 2)
    }

    @Test func oneEventPerFactPerReadingAndTheRepeatLeavesADropRow() async throws {
        let world = try await worldWithTwoFacts()
        let result = try await readDayTwo(
            world,
            [
                pipItem(cite: 20, quote: "deck", relation: "same_as", handle: "F1"),
                pipItem(
                    when: TimeJSON.inDays(9, words: "kal"), cite: 20, quote: "bhej", relation: "same_as", handle: "F1"),
                pipItem(
                    "done", "Deck sent", cite: 20, quote: "dungi", relation: "closes", handle: "F1", outcome: "kept"),
            ])
        #expect(result.links.map(\.effect) == [.restate] && result.dropped == 2)
        let drops = try world.store.queries.dropReasons(of: try #require(result.run))
        #expect(drops.map(\.rule) == [.repeatInReading, .repeatInReading] && drops.map(\.ordinal) == [1, 2])
    }

    // MARK: the other relations

    @Test func supersedesOpensANewFactAndEndsTheOldOneWithTheEvidenceLine() async throws {
        let world = try await worldWithTwoFacts()
        let result = try await readDayTwo(
            world,
            [
                pipItem(
                    "decision", "Skip the deck", cite: 20, quote: "pakka bhej dungi", relation: "supersedes",
                    handle: "F1")
            ])
        #expect(result.items.count == 1 && result.links.map(\.kind) == [.supersede])
        let old = try #require(try world.all().first { $0["kind"] == "commitment" && $0["person"] == "Asha" })
        #expect(old.closed?.outcome == "superseded" && old.closed?.quote == "pakka bhej dungi")
        let fresh = try #require(try world.open().first { $0["kind"] == "decision" })
        let successor = try world.db {
            try Int64.fetchOne($0, sql: "SELECT successor FROM item_event WHERE kind = 'supersede'")
        }
        let stillOpen = try world.open().contains { $0.id == old.id }
        #expect(successor == fresh.id && !stillOpen)
    }

    @Test func aSupersedingLineOlderThanTheFactIsRefused() async throws {
        let world = try await worldWithTwoFacts()
        let result = try await world.read(
            [pipItem("decision", "Skip", cite: 30, quote: "skip", relation: "supersedes", handle: "F1")],
            lines: [world.line(30, Days.first, 100, "skip")], day: Days.second)
        #expect(result.dropped == 1 && result.links.isEmpty)
        #expect(try world.store.queries.dropReasons(of: try #require(result.run)).map(\.rule) == [.lineBeforeFact])
    }

    @Test func unsureOpensANewFactAndFlagsIt() async throws {
        let world = try await worldWithTwoFacts()
        let result = try await readDayTwo(
            world, [pipItem("commitment", "Deck again", cite: 20, quote: "pakka bhej dungi", relation: "unsure")])
        #expect(result.items.count == 1 && result.links.map(\.kind) == [.flag])
        let fresh = try #require(try world.open().first { $0["text"] == "Deck again" })
        #expect(try world.kinds(of: try #require(fresh.id)) == ["open", "flag"])
        #expect(try world.open().count == 3, "unsure never merges")
    }

    @Test func aMachineWithNoLifecycleAsksForNoRelation() throws {
        let reader = HelperReader(spec: .pages, model: RecordedModel(ScriptedModel("{}"), store: try makeStore()))
        #expect(try !reader.schema.jsonText.contains("relation"))
        let team = HelperReader(spec: .team, model: RecordedModel(ScriptedModel("{}"), store: try makeStore()))
        let text = try team.schema.jsonText
        #expect(text.contains(#""relation""#) && Relation.names.allSatisfy { text.contains($0) })
    }
}
