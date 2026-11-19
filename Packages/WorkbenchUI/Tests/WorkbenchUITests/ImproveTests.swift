import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct ImproveTests {
    private let current =
        #"{"items":[{"task":"Review the PR","project":"","first":1,"last":1,"quote":"PR"},{"task":"Chat","project":"","first":2,"last":2,"quote":"Staff"}]}"#

    @Test func mochiProposesOneCitedFixFromTheMarksAndPutsItOnTrialAndKeepingTheBriefIsLogged() async throws {
        let clock = TestClock(.now)
        let store = try scratchStore(clock: { clock.now })
        let on = CapturePolicy(switches: [.screen: true])
        try store.savePolicy(on)
        let today = WorkDay(containing: .now)
        let days = (1...20).map { today.adding(days: -$0) }.filter { EvalSplit($0) == .dev }.prefix(3)
        var engine = CaptureEngine()
        for day in days {
            for (index, title) in ["Open PR", "Brave Staff"].enumerated() {
                clock.set(day.start.addingTimeInterval(Double(4 + index) * 3600))
                let snapshot = ScreenSnapshot(app: "App", bundleID: "a", windowID: index, title: title, text: "")
                let batch = engine.observe(snapshot, idleSeconds: 0, policy: on, at: clock.now)
                try store.record(#require(batch))
            }
            clock.set(day.start.addingTimeInterval(8 * 3600))
            let idle = ScreenSnapshot(app: "App", bundleID: "a", windowID: 9, title: "x", text: "")
            let batch = engine.observe(idle, idleSeconds: 600, policy: on, at: clock.now)
            try store.record(#require(batch))
        }
        clock.set(.now)
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let model = KeyedModel([HelperSpec.timeline.brief: current])
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" },
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: FakeNotifier())
        let timeline = try #require(crew.timeline)

        await timeline.improve()
        #expect(timeline.improveNote?.contains("Mark at least") == true && timeline.trial == nil)

        var wrong: [Int64] = []
        for day in days {
            timeline.show(day)
            await timeline.read()
            for item in timeline.items where item.quote == "Staff" {
                timeline.mark(item, as: .rejected)
                wrong.append(try #require(item.id))
            }
        }
        model.replies.withLock {
            $0["You improve one machine"] =
                #"{"kind":"add","text":"Leave out staff chats.","why":"Staff chats were marked wrong","cites":\#(wrong)}"#
        }
        await timeline.improve()
        let trial = try #require(timeline.trial)
        #expect(trial.by == .proposer && trial.why == "Staff chats were marked wrong")
        #expect(trial.version.brief == HelperSpec.timeline.brief + " Leave out staff chats.")
        #expect(trial.days.count == 3, "every marked training day is replayed")
        #expect(timeline.spec.brief == HelperSpec.timeline.brief, "the live machine does not change")

        timeline.keepCurrent()
        #expect(timeline.trial == nil)
        #expect(try store.queries.decisions(of: timeline.spec.task).map(\.kind) == [.reject, .trial])
    }
}
