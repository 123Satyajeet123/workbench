import Foundation
import Testing

@testable import WorkbenchCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 21) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private let workDay = WorkDay(containing: at(12), calendar: utc)

@Suite struct WorkDayTests {
    @Test func aNightUpdateAfterMidnightBelongsToTheDayBefore() {
        #expect(WorkDay(containing: at(1, 30, day: 22), calendar: utc) == workDay)
        #expect(WorkDay(containing: at(4, 59, day: 22), calendar: utc) == workDay)
        #expect(WorkDay(containing: at(5, 0, day: 22), calendar: utc) != workDay)
        #expect(WorkDay(containing: at(5, 0), calendar: utc) == workDay)
        #expect(WorkDay(containing: at(4, 59), calendar: utc) != workDay)
    }

    @Test func aDayReadsBackFromItsText() {
        #expect(workDay.description == "2026-09-21")
        #expect(WorkDay("2026-09-21", calendar: utc) == workDay)
        #expect(WorkDay("2026-02-30", calendar: utc) == nil)
        #expect(WorkDay("today", calendar: utc) == nil)
        #expect(workDay.adding(days: 1, calendar: utc).description == "2026-09-22")
    }
}
