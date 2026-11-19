import Foundation
import Testing

@testable import WorkbenchUI

/// The island shows one thing at a time: a recording first, then a reading machine, then waiting items.
@Suite struct IslandStateTests {
    private let since = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func aRecordingComesFirstThenAReadingThenTheQueue() {
        #expect(IslandState(recordingSince: since, reading: ["Atlas"], waiting: 3) == .recording(since: since))
        #expect(IslandState(recordingSince: nil, reading: ["Atlas"], waiting: 3) == .reading(machine: "Atlas"))
        #expect(
            IslandState(recordingSince: nil, reading: ["Atlas", "Pip"], waiting: 0) == .reading(machine: "2 machines"))
        #expect(IslandState(recordingSince: nil, reading: [], waiting: 3) == .waiting(count: 3))
        #expect(IslandState(recordingSince: nil, reading: [], waiting: 0) == .idle)
    }

    @Test func onlyTheQueueTakesAClick() {
        #expect(IslandState.waiting(count: 1).takesClicks)
        #expect(!IslandState.idle.takesClicks)
        #expect(!IslandState.reading(machine: "Atlas").takesClicks)
        #expect(!IslandState.recording(since: since).takesClicks)
    }
}

@Suite struct IslandMetricsTests {
    @Test func aScreenWithoutANotchGetsTheDefaultShapeAndThePanelHoldsBothEars() {
        let metrics = IslandMetrics(screen: nil)
        #expect(metrics.notch == IslandMetrics.defaultNotch)
        #expect(metrics.panelSize.width == metrics.notchWidth + 2 * IslandMetrics.earWidth + 40)
    }
}
