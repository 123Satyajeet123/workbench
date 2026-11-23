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

@Suite struct DevHalfTests {
    private let days = (0..<1000).map { WorkDay(containing: t0.addingTimeInterval(Double($0) * 86_400)) }

    @Test func aboutHalfTheDevDaysLearnAndEachDayAlwaysFallsTheSameWay() {
        let devDays = days.filter { EvalSplit($0) == .dev }
        let learn = devDays.filter { DevHalf($0) == .learn }.count
        #expect((devDays.count * 4 / 10...devDays.count * 6 / 10).contains(learn))
        #expect(days.allSatisfy { DevHalf($0) == DevHalf(WorkDay($0.description)!) })
    }

    @Test func heldOutDaysBelongToNeitherHalf() {
        #expect(days.filter { EvalSplit($0) == .heldOut }.allSatisfy { DevHalf($0) == nil })
        #expect(days.filter { EvalSplit($0) == .dev }.allSatisfy { DevHalf($0) != nil })
    }
}
