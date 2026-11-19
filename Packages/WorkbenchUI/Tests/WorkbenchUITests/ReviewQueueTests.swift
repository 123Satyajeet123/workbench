import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct ReviewQueueTests {
    private let blocks = #"""
        {"items":[{"task":"Review the PR","project":"app","first":1,"last":1,"quote":"PR"},
                  {"task":"Team chat","project":"","first":2,"last":2,"quote":"Staff"}]}
        """#

    /// A crew whose timeline reads one morning of screen sessions with a scripted model.
    private func crew() throws -> (Crew, ReviewModel, Store) {
        let start = Date.now.addingTimeInterval(-3 * 3600)
        let clock = TestClock(start)
        let store = try scratchStore(clock: { clock.now })
        let on = CapturePolicy(switches: [.screen: true])
        try store.savePolicy(on)
        var engine = CaptureEngine()
        for (index, title) in ["Open PR", "Brave Staff"].enumerated() {
            clock.set(start.addingTimeInterval(Double(index) * 1800))
            let snapshot = ScreenSnapshot(app: "App", bundleID: "a", windowID: index, title: title, text: "")
            let batch = engine.observe(snapshot, idleSeconds: 0, policy: on, at: clock.now)
            try store.record(#require(batch))
        }
        clock.set(start.addingTimeInterval(3600))
        let idle = ScreenSnapshot(app: "App", bundleID: "a", windowID: 9, title: "x", text: "")
        let closing = engine.observe(idle, idleSeconds: 600, policy: on, at: clock.now)
        try store.record(#require(closing))
        clock.set(.now)
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let scripted = ScriptedModel(blocks)
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" },
            makeModel: { _ in RecordedModel(scripted, store: store) }, notifier: FakeNotifier())
        return (crew, ReviewModel(store: store, crew: crew), store)
    }

    @Test func aReadFillsTheQueueAndMarkingMovesThroughItWithUndo() async throws {
        let (crew, review, store) = try crew()
        #expect(review.items.isEmpty)
        await try #require(crew.timeline).read()
        #expect(review.items.count == 2, "the queue follows a read without opening it")
        #expect(review.items.first?.askedWith != nil && review.questions == 1)
        let first = try #require(review.current?.id)
        review.mark(.confirmed)
        #expect(review.items.count == 1 && review.current?.id != first)
        #expect(crew.timeline?.items.first { $0.id == first }?.state == .confirmed, "the machine page follows")
        review.undo()
        #expect(review.items.count == 2 && review.current?.id == first)
        review.next()
        review.mark(.rejected)
        #expect(try store.queries.quality().first?.all == Tally(confirmed: 0, rejected: 1))
        review.next()
        review.previous()
        #expect(review.selected == 0)
    }
}
