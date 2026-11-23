import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// The events of a fact's life: the kinds the store accepts, who may write each, that a row never changes, and that
/// status follows valid time.
@Suite struct FactLifecycleTests {
    /// A store with one fact opened by a model reading of day one.
    private func worldWithFact() async throws -> (LifecycleWorld, Int64) {
        let world = try LifecycleWorld()
        try await world.read(
            [pipItem(cite: 1, quote: "send the deck")],
            lines: [world.line(1, Days.first, 600, "I will send the deck")])
        return (world, try #require(world.open().first?.id))
    }

    private func insert(
        _ world: LifecycleWorld, item: Int64, kind: String, actor: String, validAt: Date = t0,
        recordedAt: Date = t0, extra: String = ""
    ) throws {
        let model = actor == "model"
        try world.store.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO item_event(item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor,
                        due, successor, surface) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                    """,
                arguments: [
                    item, kind, kind.hasPrefix("close") ? "kept" : nil, model ? 1 : nil, model ? "q" : nil,
                    validAt.stored, recordedAt.stored, model ? 1 : nil, actor,
                    kind == "due_changed" ? "2026-10-01" : nil,
                    kind == "supersede" ? item : nil, actor == "person" ? MarkSurface.today.rawValue : nil,
                ])
        }
    }

    @Test func theStoreKnowsTheNineEventKindsAndTheHideKinds() {
        #expect(
            Set(EventKind.allCases.map(\.rawValue))
                == [
                    "open", "restate", "due_changed", "supersede", "close_proposed", "close", "reopen", "withdraw",
                    "flag", "hide", "snooze", "unhide", "hand_off",
                ])
    }

    @Test func everyKindAPersonOrAModelMayWriteIsAcceptedAndNoOtherIs() async throws {
        let (world, item) = try await worldWithFact()
        for kind in EventKind.modelKinds where kind != .open {
            try insert(world, item: item, kind: kind.rawValue, actor: "model")
        }
        for kind in EventKind.allCases where kind != .closeProposed && kind != .snooze {
            try insert(world, item: item, kind: kind.rawValue, actor: "person")
        }
        #expect(throws: DatabaseError.self) { try insert(world, item: item, kind: "delete", actor: "person") }
    }

    @Test func aModelNeverClosesReopensWithdrawsOrHides() async throws {
        let (world, item) = try await worldWithFact()
        for kind in ["close", "reopen", "withdraw", "hide", "unhide"] {
            #expect(throws: DatabaseError.self, "a model wrote \(kind)") {
                try insert(world, item: item, kind: kind, actor: "model")
            }
        }
        try insert(world, item: item, kind: "close_proposed", actor: "model")
    }

    @Test func aPersonNeverProposesAClose() async throws {
        let (world, item) = try await worldWithFact()
        #expect(throws: DatabaseError.self) { try insert(world, item: item, kind: "close_proposed", actor: "person") }
        try insert(world, item: item, kind: "close", actor: "person")
    }

    @Test func aRowNeverChangesExceptTheEraseOfAModelQuote() async throws {
        let (world, item) = try await worldWithFact()
        try insert(world, item: item, kind: "close_proposed", actor: "model")
        try insert(world, item: item, kind: "close", actor: "person")
        func update(_ sql: String) throws { try world.store.writer.write { try $0.execute(sql: sql) } }
        let proposed = "(SELECT MAX(id) FROM item_event WHERE kind = 'close_proposed')"
        #expect(throws: DatabaseError.self) {
            try update("UPDATE item_event SET outcome = 'dropped' WHERE id = \(proposed)")
        }
        #expect(throws: DatabaseError.self) { try update("UPDATE item_event SET valid_at = '2000-01-01T00:00:00Z'") }
        #expect(throws: DatabaseError.self) {
            try update("UPDATE item_event SET quote = 'words' WHERE id = \(proposed)")
        }
        #expect(throws: DatabaseError.self) { try update("UPDATE item_event SET kind = 'reopen' WHERE kind = 'close'") }
        try update("UPDATE item_event SET quote = '' WHERE id = \(proposed)")
        let quote = try world.db {
            try String.fetchOne($0, sql: "SELECT quote FROM item_event WHERE id = \(proposed)")
        }
        #expect(quote == "")
    }

    @Test func everyStoredItemOpensWithAnEventThatCarriesItsEvidenceOrItsActor() async throws {
        let (world, item) = try await worldWithFact()
        let rows = try world.db {
            try Row.fetchAll(
                $0, sql: "SELECT kind, actor, run_id, quote FROM item_event WHERE item_id = ?", arguments: [item])
        }
        #expect(rows.count == 1 && rows[0]["kind"] as String == "open" && rows[0]["actor"] as String == "model")
        #expect(rows[0]["quote"] as String == "send the deck" && (rows[0]["run_id"] as Int64?) != nil)
        let typed = try world.commit { db in
            try db.execute(
                sql: """
                    INSERT INTO item(task, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
                        created_at, authority) VALUES ('typed', '2026-09-21', '', 'typed', 0, 0, ?, ?, '{}', 'q', ?, 'own_words')
                    """, arguments: [t0.stored, t0.stored, t0.stored])
            return db.lastInsertedRowID
        }
        #expect(try world.kinds(of: typed) == ["open"])
        let actor = try world.db {
            try String.fetchOne($0, sql: "SELECT actor FROM item_event WHERE item_id = ?", arguments: [typed])
        }
        #expect(actor == "person")
    }

    // MARK: status by valid time

    @Test func aPersonsReopenWithALaterValidTimeBeatsAnEndingEventRecordedAfterIt() async throws {
        let (world, item) = try await worldWithFact()
        let day5 = Days.at(Days.first.adding(days: 4), 600)
        let day2 = Days.at(Days.second, 600)
        try insert(
            world, item: item, kind: "close", actor: "person", validAt: Days.at(Days.first.adding(days: 3), 600),
            recordedAt: day5)
        try insert(world, item: item, kind: "reopen", actor: "person", validAt: day5, recordedAt: day5)
        try insert(
            world, item: item, kind: "supersede", actor: "model", validAt: day2,
            recordedAt: day5.addingTimeInterval(86_400 * 2))
        #expect(try world.open().map(\.id) == [item], "the reopen of day 5 outranks a supersede that was said on day 2")
        #expect(try world.all().first { $0.id == item }?.closed == nil)
    }

    @Test func anEndingEventWithALaterValidTimeBeatsAnEarlierReopenWhateverTheRecordOrder() async throws {
        let (world, item) = try await worldWithFact()
        let early = Days.at(Days.second, 600)
        let late = Days.at(Days.second.adding(days: 3), 600)
        try insert(world, item: item, kind: "close", actor: "person", validAt: late, recordedAt: early)
        try insert(world, item: item, kind: "reopen", actor: "person", validAt: early, recordedAt: late)
        #expect(try world.open().isEmpty, "recorded last, but said first: the later close stands")
        #expect(try world.all().first { $0.id == item }?.closed?.outcome == "kept")
    }

    @Test func theSameInstantIsDecidedByRecordTimeThenId() async throws {
        let (world, item) = try await worldWithFact()
        try insert(world, item: item, kind: "close", actor: "person")
        try insert(world, item: item, kind: "reopen", actor: "person")
        #expect(try world.open().map(\.id) == [item])
        try insert(world, item: item, kind: "withdraw", actor: "person")
        #expect(try world.open().isEmpty)
        #expect(try world.all().first { $0.id == item }?.closed?.outcome == "withdrawn")
    }

    @Test func openItemsAsOfADayUseTheSameOrder() async throws {
        let (world, item) = try await worldWithFact()
        let validCloseDay2 = Days.at(Days.second, 100)
        try insert(world, item: item, kind: "close", actor: "person", validAt: validCloseDay2, recordedAt: t0)
        try insert(
            world, item: item, kind: "reopen", actor: "person", validAt: Days.at(Days.second, 50),
            recordedAt: t0.addingTimeInterval(60))
        let third = Days.second.adding(days: 1)
        #expect(try world.store.queries.openItems(of: world.task, lifecycle: world.lifecycle, asOf: third).isEmpty)
        #expect(
            try world.store.queries.openItems(of: world.task, lifecycle: world.lifecycle, asOf: Days.second).count == 1)
    }

    // MARK: closes need a person

    @Test func aModelCloseIsOnlyAProposalAndNothingClosesBySilence() async throws {
        let (world, item) = try await worldWithFact()
        world.clock.set(Days.at(Days.second, 700))
        let result = try await world.read(
            [
                pipItem(
                    "done", "Deck sent", cite: 20, quote: "deck sent", relation: "closes", handle: "F1", outcome: "kept"
                )
            ],
            lines: [world.line(20, Days.second, 600, "deck sent")], day: Days.second)
        #expect(result.links.map(\.kind) == [.closeProposed])
        world.clock.set(Days.at(Days.second.adding(days: 30), 600))
        #expect(try world.open().map(\.id).contains(item), "30 days later it is still open")
        #expect(try world.store.queries.closeProposals(of: world.task).map(\.id) == [item])
    }

    @Test func aPersonConfirmsAProposalAndTheCloseCarriesThePersonAsActor() async throws {
        let (world, item) = try await worldWithFact()
        try await world.read(
            [
                pipItem(
                    "done", "Deck sent", cite: 20, quote: "deck sent", relation: "closes", handle: "F1", outcome: "kept"
                )
            ],
            lines: [world.line(20, Days.second, 600, "deck sent")], day: Days.second)
        world.clock.set(Days.at(Days.second, 900))
        try world.store.confirmClose(item: item, surface: .today)
        let closed = try #require(try world.all().first { $0.id == item }?.closed)
        #expect(closed.outcome == "kept" && closed.quote == nil, "a person's close has no model quote")
        #expect(try world.store.queries.closeProposals(of: world.task).isEmpty)
        let actor = try world.db {
            try String.fetchOne(
                $0, sql: "SELECT actor FROM item_event WHERE item_id = ? AND kind = 'close'", arguments: [item])
        }
        #expect(actor == "person")
    }

    @Test func confirmingAnItemWithNoProposalThrowsAndChangesNothing() async throws {
        let (world, item) = try await worldWithFact()
        #expect(throws: StoreError.noCloseProposal(item: item)) {
            try world.store.confirmClose(item: item, surface: .today)
        }
        #expect(try world.open().map(\.id) == [item])
    }

    @Test func aReopenAfterAProposalIsASayNoAndAProposalAfterTheReopenIsPending() async throws {
        let (world, item) = try await worldWithFact()
        let close = pipItem(
            "done", "Deck sent", cite: 20, quote: "deck sent", relation: "closes", handle: "F1", outcome: "kept")
        try await world.read([close], lines: [world.line(20, Days.second, 600, "deck sent")], day: Days.second)
        try world.store.reopen(item: item, surface: .today)
        #expect(try world.store.queries.closeProposals(of: world.task).isEmpty)
        try await world.read(
            [
                pipItem(
                    "done", "Deck sent again", cite: 21, quote: "sent it", relation: "closes", handle: "F1",
                    outcome: "kept")
            ],
            lines: [world.line(21, Days.second, 700, "sent it")], day: Days.second, readUpTo: 20)
        #expect(try world.store.queries.closeProposals(of: world.task).map(\.id) == [item])
    }
}
