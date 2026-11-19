import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct EvalSplitTests {
    private let days = (0..<1000).map { WorkDay(containing: t0.addingTimeInterval(Double($0) * 86_400)) }

    @Test func aboutThreeDaysInTenAreHeldOutAndEachDayAlwaysFallsTheSameWay() {
        let heldOut = days.filter { EvalSplit($0) == .heldOut }.count
        #expect((250...350).contains(heldOut))
        #expect(days.allSatisfy { EvalSplit($0) == EvalSplit(WorkDay($0.description)!) })
    }

}
