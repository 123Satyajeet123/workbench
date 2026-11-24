import CaptureService
import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct TrialTests {
    private let current =
        #"{"items":[{"task":"Review the PR","project":"","first":@Open PR@,"last":@Open PR@,"quote":"PR"},{"task":"Chat","project":"","first":@Brave Staff@,"last":@Brave Staff@,"quote":"Staff"}]}"#
    private let tried =
        #"{"items":[{"task":"Review the pull request","project":"","first":@Open PR@,"last":@Open PR@,"quote":"PR"},{"task":"Write the memo","project":"","first":@Memo draft@,"last":@Memo draft@,"quote":"Memo"}]}"#

    @Test func aNewBriefIsTriedOnPastDaysBesideTheCurrentAndOnlySwitchingChangesTheMachine() async throws {
        let clock = TestClock(.now)
        let store = try scratchStore(clock: { clock.now })
        let on = CapturePolicy(switches: [.screen: true])
        try store.savePolicy(on)
        let today = WorkDay(containing: .now)
        let days = (1...14).map { today.adding(days: -$0) }.filter { DevHalf($0) == .trial }.prefix(2)
        var engine = CaptureEngine()
        for day in days {
            for (index, title) in ["Open PR", "Brave Staff", "Memo draft"].enumerated() {
                clock.set(day.start.addingTimeInterval(Double(4 + index) * 3600))
                let snapshot = ScreenSnapshot(app: "App", bundleID: "a", windowID: index, title: title, text: "")
                let batch = engine.observe(snapshot, presence: .active, policy: on, at: clock.now)
                try store.record(#require(batch))
            }
            clock.set(day.start.addingTimeInterval(8 * 3600))
            let batch = engine.observe(
                ScreenSnapshot(app: "App", bundleID: "a", windowID: 9, title: "x", text: ""), presence: .idle,
                policy: on, at: clock.now)
            try store.record(#require(batch))
        }
        clock.set(.now)
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let model = KeyedModel([HelperSpec.timeline.brief: current, "memos": tried])
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" },
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: FakeNotifier())
        let timeline = try #require(crew.screenReaders.first)
        for day in days {
            timeline.show(day)
            await timeline.read()
            for item in timeline.items where item.quote == "Staff" { timeline.mark(item, as: .rejected) }
        }

        await timeline.startTrial(brief: "Join windows into blocks; include writing memos.")
        let trial = try #require(timeline.trial)
        #expect(trial.days.count == 2)
        #expect(trial.result.same == 2 && trial.result.added.count == 2 && trial.result.dropped.count == 2)
        #expect(trial.result.better == 2 && trial.result.worse == 0 && trial.result.waiting == 2)
        #expect(timeline.spec.brief == HelperSpec.timeline.brief, "the live machine does not change")
        let review = ReviewModel(store: store, crew: crew)
        #expect(review.items.contains { review.name(of: $0) == "Timeline · new brief" })

        #expect(try store.queries.decisions(of: timeline.spec.task).map(\.kind) == [.trial])
        crew.switchToTrial(timeline)
        #expect(timeline.spec.brief == "Join windows into blocks; include writing memos.")
        let switched = try #require(try store.queries.decisions(of: timeline.spec.task).first)
        #expect(switched.kind == .promote && switched.parentBrief == HelperSpec.timeline.brief)
        #expect(timeline.trial == nil)
        #expect(try store.queries.items(of: Trial.task(of: timeline.spec.task), since: today.adding(days: -14)).isEmpty)
    }
}
