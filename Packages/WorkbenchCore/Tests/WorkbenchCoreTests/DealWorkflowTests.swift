import Foundation
import GRDB
import Synchronization
import Testing

@testable import WorkbenchCore

@Suite struct DealWorkflowTests {
    private func event(
        _ id: String, _ kind: WorkEvent.Kind, by author: String = "Asha", clock: Int, at: Date? = nil,
        _ text: String = "", replaces: [String] = [], item: LinkedItem? = nil
    ) -> WorkEvent {
        WorkEvent(
            id: id, object: "deal-1", author: author, clock: clock, at: at ?? t0.addingTimeInterval(Double(clock) * 60),
            kind: kind, text: text, replaces: replaces, item: item)
    }

    private var moves: [WorkEvent] {
        [
            event("c", .create, clock: 1, "deal"), event("t", .title, clock: 2, "Acme"),
            event("s1", .stage, clock: 3, "Inbox"),
            event("s2", .stage, by: "Kabir", clock: 4, "In conversation", replaces: ["s1"]),
            event("s3", .stage, clock: 5, "Action required", replaces: ["s2"]),
            event("s4", .stage, by: "Kabir", clock: 6, "Founder meeting", replaces: ["s3"]),
        ]
    }

    private func permutations<T>(_ items: [T]) -> [[T]] {
        guard let first = items.first else { return [[]] }
        return permutations(Array(items.dropFirst())).flatMap { rest in
            (0...rest.count).map { index in
                var next = rest
                next.insert(first, at: index)
                return next
            }
        }
    }

    @Test func aStageMoveReplaysInAnyOrderToTheSameBoard() throws {
        let board = ObjectBoard.columns(of: WorkObject.fold(moves, viewer: "Asha"), type: ObjectTypes.deal)
        #expect(board.first { $0.stage.label == "Founder meeting" }?.objects.map(\.id) == ["deal-1"])
        #expect(board.filter { !$0.objects.isEmpty }.count == 1)
        for order in permutations(moves) {
            #expect(
                ObjectBoard.columns(of: WorkObject.fold(order, viewer: "Asha"), type: ObjectTypes.deal) == board)
        }
    }

    @Test func aMoveThatDidNotSeeAnotherLeavesTheDealInBothColumnsUntilOneMoveReplacesBoth() throws {
        let events =
            moves.prefix(4) + [event("s5", .stage, by: "Kabir", clock: 5, "Rejected", replaces: ["s2"])]
            + [event("s6", .stage, clock: 5, "Action required", replaces: ["s2"])]
        let board = ObjectBoard.columns(of: WorkObject.fold(Array(events), viewer: "Asha"), type: ObjectTypes.deal)
        #expect(board.filter { !$0.objects.isEmpty }.map(\.stage.label) == ["Action required", "Rejected"])
    }

    @Test func aStageThatIsNotListedStillGetsAColumn() throws {
        let events = Array(moves.prefix(3)) + [event("s9", .stage, clock: 9, "Passed", replaces: ["s1"])]
        let board = ObjectBoard.columns(of: WorkObject.fold(events, viewer: "Asha"), type: ObjectTypes.deal)
        #expect(board.map(\.stage.label) == ObjectTypes.deal.orderedStages.map(\.label) + ["Passed"])
        #expect(board.last?.objects.map(\.id) == ["deal-1"])
    }

    @Test func eventsWrittenBeforeTheNewFieldsStillReadAndNewOnesReadInAnOlderShape() throws {
        let old =
            #"{"machine":"M","day":"2026-09-21","columns":[],"fields":{},"quote":"q","state":"proposed","audience":["Asha"]}"#
        let read = try Coding.value(LinkedItem.self, from: old)
        #expect(read.task == nil && read.itemID == nil)

        struct OlderLinkedItem: Codable {
            var machine: String
            var quote: String
            var audience: [String]
        }
        let item = Item(
            id: 9, task: "vc.deals-1", day: WorkDay(containing: t0), scope: "", source: .screenText, citeFirst: 1,
            citeLast: 1, start: t0, end: t0, fields: [:], quote: "Acme raises", run: 1)
        let machine = Machine(id: 1, name: "Deal intake", template: "vc.deals", spec: .dealIntake, state: .active)
        let linked = LinkedItem(machine: machine, item: item, audience: ["Asha"])
        #expect(linked.task == machine.task && linked.itemID == 9)
        let json = try Coding.json(linked)
        let older = try Coding.value(OlderLinkedItem.self, from: json)
        #expect(older.machine == "Deal intake" && older.quote == "Acme raises")
        #expect(try Coding.value(LinkedItem.self, from: json) == linked)
    }

    // MARK: Action required

    private final class Ticking: @unchecked Sendable {
        let now = Mutex(t0)
        func advance(_ seconds: Double) { now.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    private func store(_ time: Ticking) throws -> Store { try makeStore(clock: { time.now.withLock { $0 } }) }

    private func deal(in store: Store, at stage: String, since: Date) throws -> WorkObject {
        let events = [
            WorkEvent(id: "c", object: "deal-1", author: "Asha", clock: 1, at: since, kind: .create, text: "deal"),
            WorkEvent(id: "t", object: "deal-1", author: "Asha", clock: 2, at: since, kind: .title, text: "Acme"),
            WorkEvent(id: "s", object: "deal-1", author: "Asha", clock: 3, at: since, kind: .stage, text: stage),
        ]
        return try #require(WorkObject.fold(events, viewer: "Asha").first)
    }

    private let friday = WorkDay("2026-09-25")!

    @Test func actionRequiredMakesExactlyOneOpenDatedFactAndANewAskReplacesIt() throws {
        let time = Ticking()
        let store = try store(time)
        let deal = try deal(in: store, at: "Action required", since: t0)
        let first = try #require(
            try store.requireAction(of: deal, what: "Get the cap table from the founder", due: friday, owner: "Asha"))
        let open = try store.queries.openDealActions()
        #expect(open.map(\.id) == [first])
        #expect(open[0]["eta"] == "2026-09-25" && open[0].dueDay == friday && open[0]["deal"] == "deal-1")
        #expect(
            open[0]["text"] == "Get the cap table from the founder"
                && open[0].carries(HelperSpec.Attention.builtIn.asksMe))

        time.advance(60)
        let second = try #require(
            try store.requireAction(of: deal, what: "Get the term sheet", due: friday, owner: "Asha"))
        #expect(try store.queries.openDealActions().map(\.id) == [second])
        let all = try store.queries.dealActions(of: "deal-1")
        #expect(all.map(\.id) == [first, second] && all[0].closed?.outcome == "dropped")
        let blank = try store.requireAction(of: deal, what: "  ", due: friday, owner: "Asha")
        #expect(blank == nil)
    }

    @Test func doneOnTheFactClosesItAndSettlesTheDealAndAnOpenOrStaleOneDoesNot() throws {
        let time = Ticking()
        let store = try store(time)
        time.advance(100)
        let deal = try deal(in: store, at: "Action required", since: time.now.withLock { $0 })
        time.advance(10)
        let id = try #require(try store.requireAction(of: deal, what: "Get the cap table", due: friday, owner: "Asha"))
        #expect(DealAction.settled([deal], actions: try store.queries.dealActions()).isEmpty, "open: not settled")

        time.advance(10)
        try store.apply(.done(outcome: "done"), to: [id])
        let actions = try store.queries.dealActions()
        let stillOpen = try store.queries.openDealActions()
        #expect(actions[0].closed?.outcome == "done" && stillOpen.isEmpty)
        #expect(DealAction.settled([deal], actions: actions).map(\.id) == ["deal-1"])

        let later = try self.deal(
            in: store, at: "Action required", since: time.now.withLock { $0 }.addingTimeInterval(60))
        #expect(
            DealAction.settled([later], actions: actions).isEmpty,
            "a done from before the deal came to this stage is an earlier wait")
        let elsewhere = try self.deal(in: store, at: "Diligence", since: t0)
        #expect(DealAction.settled([elsewhere], actions: actions).isEmpty)
    }

    @Test func leavingActionRequiredByHandDropsTheOpenAction() throws {
        let time = Ticking()
        let store = try store(time)
        let deal = try deal(in: store, at: "Action required", since: t0)
        try store.requireAction(of: deal, what: "Get the cap table", due: friday, owner: "Asha")
        try store.dropActions(of: "deal-1")
        #expect(try store.queries.openDealActions().isEmpty)
        #expect(try store.queries.dealActions(of: "deal-1").first?.closed?.outcome == "dropped")
        #expect(DealAction.settled([deal], actions: try store.queries.dealActions()).isEmpty, "dropped is not done")
    }

    @Test func todayListsTheActionAndTheDerailmentWatchFollowsIt() throws {
        let time = Ticking()
        let store = try store(time)
        let pip = try store.createMachine(from: .team, name: "Pip")
        var watch = HelperSpec.derailment
        watch.follows = pip.task
        let deal = try deal(in: store, at: "Action required", since: t0)
        try store.requireAction(of: deal, what: "Get the cap table", due: friday, owner: "Asha")

        let followed = try store.queries.openItems(readBy: watch)
        #expect(followed.map(\.task) == [DealAction.task], "Sentinel reads it as an open fact")
        let needs = Needs.pick(
            facts: try store.queries.openDealActions(), findings: [], today: WorkDay(containing: t0), now: t0)
        #expect(needs.map(\.reason) == [.asks])
        let plan = DealAction.lifecycle.closing(followed)
        #expect(plan.keys.map { $0 } == [.done(outcome: "done")])
    }

    // MARK: Typed facts

    @discardableResult
    private func openAction(_ store: Store) throws -> Int64 {
        let deal = try deal(in: store, at: "Action required", since: t0)
        return try #require(try store.requireAction(of: deal, what: "Get the cap table", due: friday, owner: "Asha"))
    }

    private func typedCount(_ store: Store) throws -> Int {
        try store.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM item WHERE source = 'typed'") ?? 0 }
    }

    @Test func aDealActionIsATypedFactWithNoRun() throws {
        let store = try store(Ticking())
        let id = try openAction(store)
        let item = try #require(try store.queries.dealActions().first)
        #expect(item.id == id && item.source == .typed && item.run == nil)
        #expect(try store.queries.runs().isEmpty && store.queries.quality().isEmpty)
    }

    @Test func typedFactsNeverCountAsModelOutputEvenWhenMarked() throws {
        let store = try store(Ticking())
        let id = try openAction(store)
        try store.mark(item: id, as: .confirmed)
        #expect(try store.queries.quality().isEmpty && store.queries.runs().isEmpty)
    }

    @Test func aDeleteOfASourceKeepsTypedFactsAndEverythingRemovesThem() throws {
        let store = try store(Ticking())
        try openAction(store)
        try store.delete(.kind(.screenText, before: nil))
        try store.delete(.activities(ActivityFilter()))
        for kind in SourceKind.allCases { try store.delete(.kind(kind, before: nil)) }
        #expect(try typedCount(store) == 1)
        try store.delete(.everything(before: nil))
        #expect(try typedCount(store) == 0)
    }

    @Test func theRetentionKeepsAnOpenTypedFactAndRemovesAClosedOldOne() throws {
        let store = try store(Ticking())
        let id = try openAction(store)
        let cutoff = t0.addingTimeInterval(86_400)
        try store.delete(.everything(before: cutoff))
        #expect(try typedCount(store) == 1, "open: kept")
        try store.apply(.done(outcome: "done"), to: [id])
        try store.delete(.everything(before: t0.addingTimeInterval(-86_400)))
        #expect(try typedCount(store) == 1, "closed but newer than the cutoff: kept")
        try store.delete(.everything(before: cutoff))
        #expect(try typedCount(store) == 0, "closed and older than the cutoff: removed")
    }

    @Test func aTypedFactCannotHaveARunAndAnotherKindMustHaveOne() throws {
        let store = try store(Ticking())
        try openAction(store)
        func insert(source: String, run: String) throws {
            try store.writer.write {
                try $0.execute(
                    sql: """
                        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                            quote, created_at) VALUES ('t', \(run), '2026-11-19', '', '\(source)', 0, 0,
                            '2026-11-19T10:00:00Z', '2026-11-19T10:00:00Z', '{}', 'q', '2026-11-19T10:00:00Z')
                        """)
            }
        }
        #expect(throws: DatabaseError.self) { try insert(source: "typed", run: "1") }
        #expect(throws: DatabaseError.self) { try insert(source: "whatsapp", run: "NULL") }
    }

    // MARK: Ribbon and timeline

    @Test func theRibbonAndTheTimelineCountTheFixture() throws {
        let day = WorkDay(containing: t0)
        let item = Item(
            id: 5, task: "vc.deals-1", day: day, scope: "", source: .whatsapp, citeFirst: 1, citeLast: 1, start: t0,
            end: t0, fields: ["company": "Acme"], quote: "Acme raises", run: 1)
        let machine = Machine(id: 1, name: "Deal intake", template: "vc.deals", spec: .dealIntake, state: .active)
        let link = LinkedItem(machine: machine, item: item, audience: ["Asha"])
        let events = moves + [event("l", .link, clock: 7, item: link), event("n", .note, clock: 8, "Strong")]
        let deal = try #require(WorkObject.fold(events, viewer: "Asha").first)
        var action = Item(
            id: 8, task: DealAction.task, day: day, scope: "", source: .typed, citeFirst: 0, citeLast: 0,
            start: t0.addingTimeInterval(400), end: t0, fields: ["text": "Get the cap table", "eta": "2026-09-25"],
            quote: "Get the cap table", run: nil)
        action.closed = Item.Closed(outcome: "done", quote: nil, at: t0.addingTimeInterval(900))

        let story = DealStory.make(
            deal: deal, ratings: ["l": .hot],
            marks: ["l": [.init(state: .proposed, at: t0), .init(state: .confirmed, at: t0.addingTimeInterval(500))]],
            actions: [action])

        #expect(
            story.ribbon
                == DealStory.Ribbon(
                    sources: ["WhatsApp"], rating: .hot, mark: .confirmed, moves: 3, actionsOpened: 1,
                    actionsClosed: 1))
        #expect(
            story.entries.map(\.kind)
                == [DealStory.Entry.Kind](
                    arrayLiteral:
                        .stage, .stage, .stage, .stage, .actionOpened, .captured, .rated, .note, .marked, .actionClosed
                ))
        #expect(story.entries.map(\.at) == story.entries.map(\.at).sorted())
        #expect(story.entries.filter(\.isMachine).map(\.kind) == [.rated])
    }

    @Test func theTimelineLeavesOutAnItemTheViewerMayNotRead() throws {
        let item = Item(
            task: "vc.deals-1", day: WorkDay(containing: t0), scope: "", source: .screenText, citeFirst: 1, citeLast: 1,
            start: t0, end: t0, fields: [:], quote: "secret words", run: 1)
        let machine = Machine(id: 1, name: "Deal intake", template: "vc.deals", spec: .dealIntake, state: .active)
        let link = LinkedItem(machine: machine, item: item, audience: ["Asha"])
        let events = moves + [event("l", .link, clock: 7, item: link)]
        let deal = try #require(WorkObject.fold(events, viewer: "Kabir").first)
        let story = DealStory.make(deal: deal, ratings: [:], marks: [:], actions: [])
        #expect(story.entries.allSatisfy { !$0.text.contains("secret") } && story.ribbon.sources.isEmpty)
    }
}
