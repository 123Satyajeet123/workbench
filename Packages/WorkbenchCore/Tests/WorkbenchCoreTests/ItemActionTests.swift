import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

private let today = WorkDay(containing: t0)

private struct Fixture {
    let store: Store
    let machine: Machine
    let id: Int64

    init(kind: String = "commitment") async throws {
        store = try makeStore()
        machine = try store.createMachine(from: .team, name: "Pip")
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let (_, run) = try await model.generate(
            HelperReader.Reply.self, schema: .object([.init("items", .array(.string))]), task: machine.task,
            instructions: machine.spec.brief, input: "x", holding: [])
        let item = Item(
            task: machine.task, day: today, scope: "work", source: .whatsapp, citeFirst: 1, citeLast: 1,
            start: today.start, end: today.start,
            fields: ["person": "Asha", "project": "Deck", "kind": kind, "text": "Send the deck", "asks": "team"],
            quote: "send the deck", run: run)
        try store.saveReading(
            HelperReader.Result(items: [item], dropped: 0, run: run), of: machine.spec, day: today, scope: "work",
            grant: grant(.whatsapp, label: "work"))
        id = try #require(store.queries.items(of: machine.task, on: today).first?.id)
    }

    var item: Item { get throws { try #require(store.queries.items(of: machine.task, on: today).first) } }
    var open: [Item] { get throws { try store.queries.openItems(readBy: machine.spec).items } }

    func listed(at now: Date) throws -> Bool { try item.isListed(at: now) }
}

@Suite struct ItemActionTests {
    @Test func doneClosesWithTheOutcomeAndTheFounderAsActor() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.done(outcome: "kept"), to: [fixture.id], surface: .today)
        #expect(try fixture.item.closed?.outcome == "kept" && fixture.item.closed?.quote == nil)
        #expect(try fixture.open.isEmpty)
        let actor = try await fixture.store.writer.read {
            try String.fetchOne($0, sql: "SELECT actor FROM item_event WHERE kind = 'close'")
        }
        #expect(actor == "person")
    }

    @Test func undoingDoneOpensTheFactAgain() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.done(outcome: "kept"), to: [fixture.id], surface: .today)
        try fixture.store.undo(.done(outcome: "kept"), on: [fixture.id], surface: .today)
        #expect(try fixture.item.closed == nil)
        #expect(try fixture.open.map(\.id) == [fixture.id])
    }

    @Test func aBlockerIsResolvedAndAnythingElseIsKept() async throws {
        let lifecycle = try #require(HelperSpec.team.lifecycle)
        #expect(try await lifecycle.doneOutcome(of: Fixture(kind: "blocker").item) == "resolved")
        #expect(try await lifecycle.doneOutcome(of: Fixture(kind: "commitment").item) == "kept")
        #expect(try await lifecycle.doneOutcome(of: Fixture(kind: "question").item) == "kept")
    }

    @Test func notRelevantHidesTheFactAndCountsAsARightMark() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.notRelevant, to: [fixture.id], surface: .today)
        let item = try fixture.item
        #expect(item.hiding == .hidden && item.state == .confirmed)
        #expect(try !fixture.listed(at: t0))
        let quality = try #require(fixture.store.queries.quality().first)
        #expect(quality.all.confirmed == 1 && quality.all.rejected == 0)
    }

    @Test func undoingNotRelevantShowsTheFactAndTakesTheMarkBack() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.notRelevant, to: [fixture.id], surface: .today)
        try fixture.store.undo(.notRelevant, on: [fixture.id], surface: .today)
        let item = try fixture.item
        #expect(item.hiding == nil && item.state == .proposed)
        #expect(try fixture.listed(at: t0))
        #expect(try fixture.store.queries.quality().first?.all.marked == 0)
    }

    @Test func wrongHidesTheFactAndCountsAsAWrongMark() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.wrong, to: [fixture.id], surface: .today)
        let item = try fixture.item
        #expect(item.hiding == .hidden && item.state == .rejected)
        let quality = try #require(fixture.store.queries.quality().first)
        #expect(quality.all.rejected == 1 && quality.all.confirmed == 0)
    }

    @Test func undoingWrongShowsTheFactAndTakesTheMarkBack() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.wrong, to: [fixture.id], surface: .today)
        try fixture.store.undo(.wrong, on: [fixture.id], surface: .today)
        let item = try fixture.item
        #expect(item.hiding == nil && item.state == .proposed)
        #expect(try fixture.listed(at: t0))
    }

    @Test func aSnoozeHidesTheFactUntilItsDayStartsAndThenItComesBack() async throws {
        let fixture = try await Fixture()
        let until = today.adding(days: 2)
        try fixture.store.apply(.snooze(until: until), to: [fixture.id], surface: .today)
        let item = try fixture.item
        #expect(item.hiding == .snoozed(until: until.start) && item.state == .proposed)
        #expect(try !fixture.listed(at: until.start.addingTimeInterval(-1)))
        #expect(try fixture.listed(at: until.start))
    }

    @Test func undoingASnoozeShowsTheFactAtOnce() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.snooze(until: today.adding(days: 2)), to: [fixture.id], surface: .today)
        try fixture.store.undo(.snooze(until: today.adding(days: 2)), on: [fixture.id], surface: .today)
        #expect(try fixture.item.hiding == nil)
        #expect(try fixture.listed(at: t0))
    }

    @Test func aHiddenFactStaysOpenAndOnItsMachinesOwnPage() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.notRelevant, to: [fixture.id], surface: .today)
        #expect(try fixture.open.map(\.id) == [fixture.id])
        #expect(try fixture.store.queries.items(of: fixture.machine.task, day: today, scope: "work").count == 1)
    }

    @Test func aHideDoesNotCloseAndACloseDoesNotHide() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.done(outcome: "kept"), to: [fixture.id], surface: .today)
        #expect(try fixture.item.hiding == nil)
        try fixture.store.apply(.snooze(until: today.adding(days: 1)), to: [fixture.id], surface: .today)
        #expect(try fixture.item.closed?.outcome == "kept")
        try fixture.store.undo(.snooze(until: today.adding(days: 1)), on: [fixture.id], surface: .today)
        #expect(try fixture.item.closed?.outcome == "kept" && fixture.item.hiding == nil)
    }

    @Test func oneActionOnManyFactsIsOneTransactionAndAFailureChangesNone() async throws {
        let fixture = try await Fixture()
        #expect(throws: (any Error).self) {
            try fixture.store.apply(.done(outcome: ""), to: [fixture.id], surface: .today)
        }
        #expect(try fixture.item.closed == nil)
        #expect(throws: (any Error).self) { try fixture.store.apply(.wrong, to: [fixture.id, 999], surface: .today) }
        #expect(try fixture.item.state == .proposed && fixture.item.hiding == nil)
    }

    @Test func aModelCanOnlyEverCloseAnItem() async throws {
        let fixture = try await Fixture()
        #expect(throws: (any Error).self) {
            try fixture.store.writer.write {
                try $0.execute(
                    sql: """
                        INSERT INTO item_event(item_id, kind, line_id, quote, valid_at, recorded_at, run_id, actor)
                        VALUES (\(fixture.id), 'hide', 1, 'q', '2026-09-21T00:00:00Z', '2026-09-21T00:00:00Z', 1, 'model')
                        """)
            }
        }
    }

    @Test func aSnoozeNeedsADateAndNothingElseHasOne() async throws {
        let fixture = try await Fixture()
        for kind in ["snooze", "hide"] {
            let bound = kind == "snooze" ? "NULL" : "'2026-09-22T00:00:00Z'"
            #expect(throws: (any Error).self) {
                try fixture.store.writer.write {
                    try $0.execute(
                        sql: """
                            INSERT INTO item_event(item_id, kind, valid_at, recorded_at, actor, until)
                            VALUES (\(fixture.id), '\(kind)', '2026-09-21T00:00:00Z', '2026-09-21T00:00:00Z', 'person', \(bound))
                            """)
                }
            }
        }
    }
}

/// Each mark of a person is one event of the person on a surface.
@Suite struct MarkSurfaceTests {
    private struct Event: Equatable {
        var kind: String
        var actor: String
        var surface: String?
    }

    private func events(_ fixture: Fixture, after count: Int = 1) async throws -> [Event] {
        try await fixture.store.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT kind, actor, surface FROM item_event ORDER BY id").dropFirst(count).map {
                Event(kind: $0["kind"], actor: $0["actor"], surface: $0["surface"])
            }
        }
    }

    @Test func theSurfacesAreTheNamedOnesAndTheStoreKeepsTheirNames() {
        #expect(
            Set(MarkSurface.allCases.map(\.rawValue))
                == ["today", "review", "notification", "menu_bar", "island", "machine_page", "deals"])
    }

    @Test func eachMarkIsOneEventOfThePersonOnTheSurfaceItWasMadeOn() async throws {
        let actions: [(ItemAction, String)] = [
            (.done(outcome: "kept"), "close"), (.notRelevant, "hide"), (.wrong, "hide"),
            (.snooze(until: today.adding(days: 1)), "snooze"), (.handOff(to: "Raj"), "hand_off"),
        ]
        for surface in MarkSurface.allCases {
            for (action, kind) in actions {
                let fixture = try await Fixture()
                try fixture.store.apply(action, to: [fixture.id], surface: surface)
                #expect(try await events(fixture) == [Event(kind: kind, actor: "person", surface: surface.rawValue)])
            }
        }
    }

    @Test func undoingAMarkIsAnEventOnTheSurfaceOfTheUndo() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.done(outcome: "kept"), to: [fixture.id], surface: .today)
        try fixture.store.undo(.done(outcome: "kept"), on: [fixture.id], surface: .notification)
        #expect(
            try await events(fixture) == [
                Event(kind: "close", actor: "person", surface: "today"),
                Event(kind: "reopen", actor: "person", surface: "notification"),
            ])
    }

    @Test func wrongKeepsFeedingTheRejectedStateAndNotRelevantTheConfirmedOne() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.wrong, to: [fixture.id], surface: .menuBar)
        #expect(try fixture.item.state == .rejected)
        try fixture.store.undo(.wrong, on: [fixture.id], surface: .menuBar)
        try fixture.store.apply(.notRelevant, to: [fixture.id], surface: .menuBar)
        #expect(try fixture.item.state == .confirmed)
    }

    @Test func theByHandCloseReopenAndWithdrawEachNameTheirSurface() async throws {
        let fixture = try await Fixture()
        try fixture.store.close(item: fixture.id, as: "kept", surface: .machinePage)
        try fixture.store.reopen(item: fixture.id, surface: .machinePage)
        try fixture.store.withdraw(item: fixture.id, surface: .island)
        #expect(try await events(fixture).map(\.surface) == ["machine_page", "machine_page", "island"])
    }

    @Test func aHandOffMovesTheOwnerAndUndoGivesTheFactBack() async throws {
        let fixture = try await Fixture()
        try fixture.store.apply(.handOff(to: "Raj"), to: [fixture.id], surface: .today)
        #expect(try fixture.item.handedTo == "Raj")
        try fixture.store.apply(.handOff(to: "Mia"), to: [fixture.id], surface: .today)
        #expect(try fixture.item.handedTo == "Mia", "the latest hand off stands")
        try fixture.store.undo(.handOff(to: "Mia"), on: [fixture.id], surface: .today)
        #expect(try fixture.item.handedTo == nil)
    }

    @Test func aHandOffToNoOneNamedIsRefused() async throws {
        let fixture = try await Fixture()
        #expect(throws: (any Error).self) {
            try fixture.store.apply(.handOff(to: ""), to: [fixture.id], surface: .today)
        }
        #expect(try await events(fixture).isEmpty)
    }

    @Test func theStoreRefusesAMarkOfAPersonWithNoSurfaceAndAnUnknownSurface() async throws {
        let fixture = try await Fixture()
        let insert = { (surface: String?) in
            try fixture.store.writer.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO item_event(item_id, kind, valid_at, recorded_at, actor, surface)
                        VALUES (?, 'unhide', '2026-11-23T08:00:00Z', '2026-11-23T08:00:00Z', 'person', ?)
                        """, arguments: [fixture.id, surface])
            }
        }
        #expect(throws: (any Error).self) { try insert(nil) }
        #expect(throws: (any Error).self) { try insert("fax") }
        try insert("today")
    }
}
