import Foundation
import WorkbenchCore

struct NudgeSchedule: Codable, Equatable {
    var isOn = false
    var hour = 21
    var minute = 30

    func isDue(at now: Date, lastSent: WorkDay?, calendar: Calendar = .current) -> Bool {
        let day = WorkDay(containing: now, calendar: calendar)
        guard isOn, lastSent != day, let time = time(on: day, calendar: calendar) else { return false }
        return now >= time
    }

    func time(on day: WorkDay, calendar: Calendar = .current) -> Date? {
        let midnight = calendar.startOfDay(for: day.start)
        let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: midnight)
        return time.flatMap { $0 < day.start ? calendar.date(byAdding: .day, value: 1, to: $0) : $0 }
    }
}

struct WatchSchedule: Codable, Equatable {
    var isOn = false
    var everyMinutes = 60
    var fromHour = 9
    var untilHour = 22

    func isDue(at now: Date, lastRead: Date?, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        guard isOn, (fromHour..<untilHour).contains(hour) else { return false }
        return lastRead.map { now.timeIntervalSince($0) >= Double(everyMinutes * 60) } ?? true
    }

    func nextRun(after lastRead: Date?, now: Date, calendar: Calendar = .current) -> Date? {
        guard isOn else { return nil }
        let earliest = max(now, lastRead.map { $0.addingTimeInterval(Double(everyMinutes * 60)) } ?? now)
        let hour = calendar.component(.hour, from: earliest)
        if (fromHour..<untilHour).contains(hour) { return earliest }
        guard let opening = calendar.date(bySettingHour: fromHour, minute: 0, second: 0, of: earliest) else {
            return nil
        }
        return hour < fromHour ? opening : calendar.date(byAdding: .day, value: 1, to: opening)
    }
}
