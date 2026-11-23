import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

struct JoinButtonTests {
    @Test func joinStandsOutFromTenMinutesBeforeUntilTheMeetingEnds() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let meeting = Meeting(id: "1", calendar: "c", title: "Sync", start: start, end: start.addingTimeInterval(1800))
        #expect(!JoinButton.isDue(meeting, at: start.addingTimeInterval(-11 * 60)))
        #expect(JoinButton.isDue(meeting, at: start.addingTimeInterval(-9 * 60)))
        #expect(JoinButton.isDue(meeting, at: start.addingTimeInterval(1799)))
        #expect(!JoinButton.isDue(meeting, at: start.addingTimeInterval(1800)))
    }
}
