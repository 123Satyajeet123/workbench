import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// The first morning list offers to mark the old backlog as handled: one bulk event, nothing deleted, all of it
/// reopenable.
@Suite struct FirstRunCutoffTests {
    /// Three open facts opened on days 0, 5 and 10 before day 10's reading, and a clock on day 10.
    private func backlog() async throws -> (LifecycleWorld, [Int64]) {
        let world = try LifecycleWorld()
        for (number, offset) in [(1, 0), (2, 5), (3, 10)] {
            let day = Days.first.adding(days: offset)
            world.clock.set(Days.at(day, 600))
            try await world.read(
                [pipItem("commitment", text(number), cite: number, quote: "q\(number)")],
                lines: [world.line(Int64(number), day, 600, "q\(number)")], day: day)
        }
        let ids = try world.open().compactMap(\.id).sorted()
        world.clock.set(Days.at(Days.first.adding(days: 10), 700))
        return (world, ids)
    }

    private func text(_ number: Int) -> String { "commitment \(number)" }

    private var today: WorkDay { Days.first.adding(days: 10) }

    @Test func theCutoffTakesTheOpenFactsOlderThanNDaysAndLeavesTheNewerOnes() async throws {
        let (world, _) = try await backlog()
        let older = FirstRun.older(try world.open(), thanDays: 7, today: today)
        #expect(older.count == 1, "only the fact of day 0 is older than 7 days")
        #expect(FirstRun.older(try world.open(), thanDays: 3, today: today).count == 2)
        #expect(FirstRun.older(try world.open(), thanDays: 30, today: today).isEmpty)
    }

    @Test func theDefaultNumberOfDaysIsSevenFromSuperhumansCutoff() {
        #expect(FirstRun.defaultDays == 7 && MorningSettings().cutoffDays == 7)
    }

    @Test func markingHandledWritesOneBulkEventOfThePersonAndClosesEachFactWithTheOutcomeHandled() async throws {
        let (world, ids) = try await backlog()
        let batch = try #require(
            try world.store.markHandled(
                Array(ids.prefix(2)), olderThanDays: 3, cutoff: today.adding(days: -3), surface: .today))
        let rows = try world.db {
            try Row.fetchAll($0, sql: "SELECT actor, surface, older_than_days FROM handled_batch")
        }
        #expect(rows.count == 1 && rows[0]["actor"] as String == "person" && rows[0]["surface"] as String == "today")
        let closes = try world.db {
            try Row.fetchAll(
                $0,
                sql: "SELECT item_id, outcome, actor, batch_id FROM item_event WHERE kind = 'close' ORDER BY item_id")
        }
        #expect(closes.map { $0["item_id"] as Int64 } == Array(ids.prefix(2)))
        #expect(closes.allSatisfy { ($0["outcome"] as String) == "handled" && ($0["actor"] as String) == "person" })
        #expect(closes.allSatisfy { ($0["batch_id"] as Int64) == batch.id })
        #expect(try world.open().compactMap(\.id) == [ids[2]])
    }

    @Test func nothingIsDeletedAndTheFactsStayWithTheirQuotesAndEvents() async throws {
        let (world, ids) = try await backlog()
        let before = try world.all().count
        try world.store.markHandled(ids, olderThanDays: 3, cutoff: today.adding(days: -3), surface: .today)
        #expect(try world.all().count == before, "the first run deletes facts")
        let closed = try world.all().filter { $0.closed?.outcome == "handled" }
        #expect(closed.count == 3 && closed.allSatisfy { !$0.quote.isEmpty })
    }

    @Test func reopeningTheBatchBringsEveryFactBackAndLeavesAFactClosedAgainSinceAlone() async throws {
        let (world, ids) = try await backlog()
        let batch = try #require(
            try world.store.markHandled(ids, olderThanDays: 3, cutoff: today.adding(days: -3), surface: .today))
        try world.store.reopen(item: ids[0], surface: .today)
        try world.store.close(item: ids[0], as: "kept", surface: .today)
        try world.store.reopenHandled(batch: batch.id, surface: .today)
        #expect(try world.open().compactMap(\.id).sorted() == [ids[1], ids[2]])
        #expect(try world.all().first { $0.id == ids[0] }?.closed?.outcome == "kept", "a later close stands")
    }

    @Test func aFactAlreadyClosedIsNotClosedAgainAndAnEmptyBatchWritesNothing() async throws {
        let (world, ids) = try await backlog()
        try world.store.close(item: ids[0], as: "kept", surface: .today)
        #expect(try world.store.markHandled([ids[0]], olderThanDays: 3, cutoff: today, surface: .today) == nil)
        #expect(try world.db { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM handled_batch") } == 0)
    }

    @Test func theLatestBatchIsReadBack() async throws {
        let (world, ids) = try await backlog()
        #expect(try world.store.queries.latestHandledBatch() == nil)
        let batch = try #require(
            try world.store.markHandled(ids, olderThanDays: 4, cutoff: today.adding(days: -4), surface: .menuBar))
        let read = try #require(try world.store.queries.latestHandledBatch())
        #expect(read.id == batch.id && read.olderThanDays == 4 && read.surface == .menuBar)
    }
}
