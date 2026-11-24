import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct ImproveTests {
    private let current =
        #"{"items":[{"task":"Review the PR","project":"","first":@Open PR@,"last":@Open PR@,"quote":"PR"},{"task":"Chat","project":"","first":@Brave Staff@,"last":@Brave Staff@,"quote":"Staff"}]}"#

    @Test func mochiProposesOneCitedFixFromTheMarksAndPutsItOnTrialAndKeepingTheBriefIsLogged() async throws {
        let clock = TestClock(.now)
        let store = try scratchStore(clock: { clock.now })
        let on = CapturePolicy(switches: [.screen: true])
        try store.savePolicy(on)
        let today = WorkDay(containing: .now)
        let recent = (1...20).map { today.adding(days: -$0) }
        let learnDays = Array(recent.filter { DevHalf($0) == .learn }.prefix(3))
        let trialDays = Array(recent.filter { DevHalf($0) == .trial }.prefix(2))
        let days = learnDays + trialDays
        var engine = CaptureEngine()
        for day in days {
            for (index, title) in ["Open PR", "Brave Staff"].enumerated() {
                clock.set(day.start.addingTimeInterval(Double(4 + index) * 3600))
                let snapshot = ScreenSnapshot(app: "App", bundleID: "a", windowID: index, title: title, text: "")
                let batch = engine.observe(snapshot, presence: .active, policy: on, at: clock.now)
                try store.record(#require(batch))
            }
            clock.set(day.start.addingTimeInterval(8 * 3600))
            let idle = ScreenSnapshot(app: "App", bundleID: "a", windowID: 9, title: "x", text: "")
            let batch = engine.observe(idle, presence: .idle, policy: on, at: clock.now)
            try store.record(#require(batch))
        }
        clock.set(.now)
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let model = KeyedModel([HelperSpec.timeline.brief: current])
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" },
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: FakeNotifier())
        let timeline = try #require(crew.screenReaders.first)

        await timeline.improve()
        #expect(timeline.improveNote?.contains("Mark at least") == true && timeline.trial == nil)

        var wrong: [Int64] = []
        for day in days {
            timeline.show(day)
            await timeline.read()
            for item in timeline.items where item.quote == "Staff" {
                timeline.mark(item, as: .rejected)
                if learnDays.contains(day) { wrong.append(try #require(item.id)) }
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
        #expect(Set(trial.days) == Set(trialDays), "every marked trial day is replayed, and no learn day")
        let judged = (trial.result.dropped + trial.result.added).compactMap(\.id)
        #expect(Set(wrong).isDisjoint(with: judged), "an item the edit cites is never a trial outcome")
        #expect(timeline.spec.brief == HelperSpec.timeline.brief, "the live machine does not change")

        timeline.keepCurrent()
        #expect(timeline.trial == nil)
        #expect(try store.queries.decisions(of: timeline.spec.task).map(\.kind) == [.reject, .trial])
    }
}
