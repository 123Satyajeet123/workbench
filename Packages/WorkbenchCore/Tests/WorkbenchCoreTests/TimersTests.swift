import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// The pure function from a fact to its timers, and how the lifecycle arms, cancels and moves them.
@Suite struct TimerRowsTests {
    private let opened = Date(timeIntervalSince1970: 1_790_000_000)
    private func due(_ source: Due.Source = .resolved, after: TimeInterval = 86_400) -> Due {
        Due(
            utc: opened.addingTimeInterval(after), zone: "Asia/Kolkata", source: source, precision: .day,
            record: nil)
    }

    private func fact(due: Due?, kind: String = "commitment") -> TimerFact {
        TimerFact(task: "team.ledger", fields: ["kind": kind], opened: opened, due: due)
    }

    @Test func aFactWithADueTimeHasOneDueTimerAtThatTimeInItsZone() {
        let rows = Timers.rows(of: fact(due: due()), policies: [])
        #expect(rows.count == 1 && rows[0].kind == .due && rows[0].fireAt == opened.addingTimeInterval(86_400))
        #expect(rows[0].zone == "Asia/Kolkata" && rows[0].source == .resolved && rows[0].precision == .day)
    }

    @Test func aFactWithNoDueTimeHasNoDueTimer() {
        #expect(Timers.rows(of: fact(due: nil), policies: []).isEmpty)
        let none = Due.unresolved(.none, zone: TimeZone(identifier: "Asia/Kolkata")!)
        #expect(Timers.rows(of: fact(due: none), policies: []).isEmpty)
    }

    @Test func aPolicyTimesTheFactsOfItsMachineAndValueFromTheirOpening() {
        let policy = SLAPolicy(id: 3, task: "team.ledger", field: "kind", value: "question", duration: 3_600)
        let question = Timers.rows(of: fact(due: nil, kind: "question"), policies: [policy])
        #expect(question.map(\.kind) == [.sla] && question[0].fireAt == opened.addingTimeInterval(3_600))
        #expect(question[0].source == .default && question[0].policy == 3)
        #expect(Timers.rows(of: fact(due: nil, kind: "plan"), policies: [policy]).isEmpty, "another value")
        let other = SLAPolicy(id: 4, task: "other.machine", field: "kind", value: "question", duration: 60)
        #expect(Timers.rows(of: fact(due: nil, kind: "question"), policies: [other]).isEmpty, "another machine")
    }

    @Test func aTimerFiresWhenItsTimeHasComeAndNotBefore() {
        let now = opened.addingTimeInterval(100)
        let decided = Timers.decide([(1, now.addingTimeInterval(-10)), (2, now.addingTimeInterval(10))], now: now)
        #expect(decided.map(\.id) == [1] && decided.map(\.outcome) == [.fired])
    }

    @Test func aTimerFoundTooLateIsSkippedAndTheCatchUpIsLimited() {
        let now = opened.addingTimeInterval(10 * 86_400)
        var settings = TimerSettings()
        settings.catchUpLimit = 2
        let pending = [
            (id: Int64(1), fireAt: now.addingTimeInterval(-5 * 86_400)),
            (id: Int64(2), fireAt: now.addingTimeInterval(-300)), (id: Int64(3), fireAt: now.addingTimeInterval(-200)),
            (id: Int64(4), fireAt: now.addingTimeInterval(-100)),
        ]
        let decided = Timers.decide(pending, now: now, settings: settings)
        #expect(decided.map(\.id) == [1, 2, 3], "the stale one is skipped; two fire; the last waits")
        #expect(decided.map(\.outcome) == [.skipStale, .fired, .fired])
    }
}

@Suite struct TimerLifecycleTests {
    /// Asha's commitment F1 is due four days after day one; Raj's has no due time.
    private func world() async throws -> (LifecycleWorld, asha: Int64, raj: Int64) {
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
        let open = try world.open()
        return (world, try #require(open.first { $0["person"] == "Asha" }?.id), try #require(open.last?.id))
    }

    private func timers(_ world: LifecycleWorld, _ item: Int64) throws -> [StoredTimer] {
        try world.store.queries.timers(of: item)
    }

    private func pastDue(_ world: LifecycleWorld) { world.clock.set(Days.first.adding(days: 6).start) }

    @Test func aFactIsOpenedWithItsDueTimerAndAFactWithNoDueTimeHasNone() async throws {
        let (world, asha, raj) = try await world()
        let own = try timers(world, asha)
        #expect(own.count == 1 && own[0].kind == .due && !own[0].isCancelled && own[0].outcome == nil)
        #expect(own[0].source == .resolved)
        #expect(own[0].fireAt == (try #require(try world.open().first { $0.id == asha }?.due?.utc)))
        #expect(try timers(world, raj).isEmpty)
    }

    @Test func aTimerFiresOnceForItsWindowAndANewPassFiresNothing() async throws {
        let (world, asha, _) = try await world()
        #expect(try world.store.fireTimers().isEmpty, "not yet")
        pastDue(world)
        let fired = try world.store.fireTimers()
        #expect(fired.map(\.item) == [asha] && fired.map(\.outcome) == [.fired] && fired.map(\.kind) == [.due])
        #expect(try world.store.fireTimers().isEmpty, "the window is decided")
        #expect(try timers(world, asha).map(\.outcome) == [.fired])
    }

    @Test func aWindowCannotBeDecidedTwiceInTheStore() async throws {
        let (world, asha, _) = try await world()
        pastDue(world)
        try world.store.fireTimers()
        let timer = try #require(try timers(world, asha).first?.id)
        #expect(throws: DatabaseError.self) {
            try world.commit {
                try $0.execute(
                    sql: """
                        INSERT INTO timer_fired(timer_id, window_key, decided_at, outcome)
                        SELECT id, fire_at, 'now', 'fired' FROM timer WHERE id = ?
                        """, arguments: [timer])
            }
        }
    }

    @Test func aFiredTimerNeverClosesTheFactAndWritesNoEventOnIt() async throws {
        let (world, asha, _) = try await world()
        pastDue(world)
        try world.store.fireTimers()
        let fact = try #require(try world.open().first { $0.id == asha })
        #expect(fact.closed == nil && fact.proposedClose == nil, "still open, nothing proposed")
        #expect(try world.kinds(of: asha) == ["open"])
        #expect(try world.open().count == 2)
    }

    @Test func aTimerFoundTooLateIsSkippedNotFired() async throws {
        let (world, asha, _) = try await world()
        world.clock.set(Days.first.adding(days: 30).start)
        let fired = try world.store.fireTimers()
        #expect(fired.map(\.outcome) == [.skipStale])
        #expect(try timers(world, asha).map(\.outcome) == [.skipStale])
    }

    @Test(arguments: ["close", "withdraw", "supersede"])
    func aFactThatEndsCancelsItsTimerAndANewPassFiresNothing(_ ending: String) async throws {
        let (world, asha, _) = try await world()
        switch ending {
        case "close": try world.store.close(item: asha, as: "kept")
        case "withdraw": try world.store.withdraw(item: asha)
        default:
            try await world.read(
                [
                    pipItem(
                        "commitment", "Send the deck later", cite: 20, quote: "kal", relation: "supersedes",
                        handle: "F1")
                ],
                lines: [world.line(20, Days.second, 600, "deck kal")], day: Days.second)
        }
        #expect(try timers(world, asha).map(\.isCancelled) == [true], "\(ending)")
        pastDue(world)
        #expect(try world.store.fireTimers().isEmpty, "a cancelled timer never fires")
    }

    @Test func aReopenedFactGetsItsTimerBack() async throws {
        let (world, asha, _) = try await world()
        try world.store.close(item: asha, as: "kept")
        try world.store.reopen(item: asha)
        #expect(try timers(world, asha).map(\.isCancelled) == [false])
        pastDue(world)
        #expect(try world.store.fireTimers().map(\.item) == [asha])
    }

    @Test func aNewDueTimeMovesTheTimer() async throws {
        let (world, asha, _) = try await world()
        let before = try #require(try timers(world, asha).first)
        try await world.read(
            [
                pipItem(
                    when: TimeJSON.inDays(8, words: "kal"), cite: 20, quote: "pakka bhej dungi",
                    relation: "same_as", handle: "F1")
            ],
            lines: [world.line(20, Days.second, 600, "deck kal pakka bhej dungi")], day: Days.second)
        let now = try timers(world, asha)
        #expect(now.count == 2)
        #expect(now.first { $0.id == before.id }?.isCancelled == true, "the old time is cancelled")
        let moved = try #require(now.first { $0.id != before.id })
        #expect(!moved.isCancelled && moved.fireAt > before.fireAt)
        world.clock.set(before.fireAt.addingTimeInterval(3_600))
        #expect(try world.store.fireTimers().isEmpty, "the old time passed and nothing fires")
        world.clock.set(moved.fireAt.addingTimeInterval(3_600))
        #expect(try world.store.fireTimers().map(\.timer) == [moved.id])
    }

    @Test func anAmbiguousNewTimeDoesNotMoveTheTimer() async throws {
        let (world, asha, _) = try await world()
        let ambiguous = TimeJSON.record("future", offset: 1, precision: "day", ambiguous: true, words: "kal")
        try await world.read(
            [pipItem(when: ambiguous, cite: 20, quote: "pakka", relation: "same_as", handle: "F1")],
            lines: [world.line(20, Days.second, 600, "deck kal pakka bhej dungi")], day: Days.second)
        #expect(try timers(world, asha).map(\.isCancelled) == [false])
        #expect(try world.kinds(of: asha) == ["open", "restate"])
    }

    @Test func aPolicyAddsATimerWhenTheFactIsOpenedAndEndingTheFactCancelsIt() async throws {
        let world = try LifecycleWorld()
        try world.store.addSLAPolicy(task: world.task, field: "kind", value: "question", duration: 3_600)
        try await world.read(
            [pipItem("question", "Hire a designer?", person: "Raj", cite: 2, quote: "hire a designer")],
            lines: [world.line(2, Days.first, 610, "do we hire a designer?")])
        let question = try #require(try world.open().first?.id)
        let own = try timers(world, question)
        #expect(own.map(\.kind) == [.sla] && own[0].source == .default)
        try world.store.close(item: question, as: "answered")
        #expect(try timers(world, question).map(\.isCancelled) == [true])
    }

    @Test func deletingAFactDeletesItsTimers() async throws {
        let (world, asha, _) = try await world()
        pastDue(world)
        try world.store.fireTimers()
        try world.commit { try $0.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [asha]) }
        let left = try world.db {
            try Int.fetchOne($0, sql: "SELECT (SELECT COUNT(*) FROM timer) + (SELECT COUNT(*) FROM timer_fired)")
        }
        #expect(left == 0)
    }
}
