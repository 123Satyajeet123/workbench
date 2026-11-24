import Foundation
import WorkbenchCore

struct NudgeSchedule: Codable, Equatable {
    var isOn = false
    var hour = 21
    var minute = 30

    /// Due from the chosen time until the work day ends, once per day. A Mac that sleeps through the time nudges on wake.
    func isDue(at now: Date, lastSent: WorkDay?, calendar: Calendar = .current) -> Bool {
        let day = WorkDay(containing: now, calendar: calendar)
        guard isOn, lastSent != day, let time = time(on: day, calendar: calendar) else { return false }
        return now >= time
    }

    /// The chosen time inside the work day, which runs from 05:00 to 05:00.
    func time(on day: WorkDay, calendar: Calendar = .current) -> Date? {
        let midnight = calendar.startOfDay(for: day.start)
        let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: midnight)
        return time.flatMap { $0 < day.start ? calendar.date(byAdding: .day, value: 1, to: $0) : $0 }
    }
}
