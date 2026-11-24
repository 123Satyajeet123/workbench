import Foundation

/// When a machine reads by itself: every `everyMinutes` between two hours of the day. The person sets it; the store
/// keeps it under `stateKey`, and the time of the last scheduled attempt under `lastReadKey`. Both names are in
/// stores already.
public struct WatchSchedule: Codable, Equatable, Sendable {
    public var isOn = false
    public var everyMinutes = 60
    public var fromHour = 9
    public var untilHour = 22

    public init(isOn: Bool = false, everyMinutes: Int = 60, fromHour: Int = 9, untilHour: Int = 22) {
        self.isOn = isOn
        self.everyMinutes = everyMinutes
        self.fromHour = fromHour
        self.untilHour = untilHour
    }

    public static func stateKey(of task: String) -> String { "\(task).watch" }
    public static func lastReadKey(of task: String) -> String { "\(task).watched" }

    public static func standard(for source: SourceDescriptor) -> WatchSchedule {
        WatchSchedule(isOn: source.retention == .chat)
    }

    public func isDue(at now: Date, lastRead: Date?, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        guard isOn, (fromHour..<untilHour).contains(hour) else { return false }
        return lastRead.map { now.timeIntervalSince($0) >= Double(everyMinutes * 60) } ?? true
    }

    /// When the next reading falls: the interval after the last one, moved to the start of the reading hours when it
    /// falls outside them. Nil while the schedule is off.
    public func nextRun(after lastRead: Date?, now: Date, calendar: Calendar = .current) -> Date? {
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

extension Queries {
    /// The schedule saved for `task`, or the standard one for its source.
    public func watchSchedule(of task: String, source: SourceDescriptor) throws -> WatchSchedule {
        guard let text = try state(forKey: WatchSchedule.stateKey(of: task)), !text.isEmpty else {
            return .standard(for: source)
        }
        return try JSONDecoder().decode(WatchSchedule.self, from: Data(text.utf8))
    }

    /// When the schedule last started a reading of `task`; nil when it never did.
    public func lastScheduledRead(of task: String) throws -> Date? {
        try state(forKey: WatchSchedule.lastReadKey(of: task)).flatMap { try? Date($0, strategy: .iso8601) }
    }
}
