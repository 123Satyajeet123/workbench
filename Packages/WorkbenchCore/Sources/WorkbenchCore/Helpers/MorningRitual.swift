import Foundation

/// What the person sets for the morning list.
public struct MorningSettings: Codable, Equatable, Sendable {
    /// Off until the person turns it on, like the other notifications.
    public var isOn = false
    /// The hour of the morning notification, in the person's day. The default is the hour of the morning brief
    /// and of the first review digest.
    public var hour = 9
    /// The backlog cutoff the first morning list offers: facts older than this many days (research P1 §3.2).
    public var cutoffDays = FirstRun.defaultDays

    /// The hours the person may choose: after a work day starts and before noon.
    public static let hours = WorkDay.startHour...11

    public init() {}
}

/// The rules of the one morning notification. Pure: the app reads the clock and the presence, and does what the
/// rules say.
public enum MorningRitual {
    public enum Readiness: Equatable, Sendable {
        /// The morning hour has not come.
        case notYet
        /// The notification budget of this day is spent: one a day.
        case spent
        /// The person is not at the Mac: locked, asleep or the screen off. Wait for the first active moment.
        case away
        case ready
    }

    /// Whether the morning notification may be decided now. `lastDecided` is the day the last decision was made,
    /// whether it posted or kept silent.
    public static func readiness(
        now: Date, hour: Int, lastDecided: WorkDay?, presence: PresenceState, zone: TimeZone = .current
    ) -> Readiness {
        let calendar = Calendar.gregorian(in: zone)
        let today = day(of: now, zone: zone)
        guard let morning = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today.start), now >= morning
        else { return .notYet }
        guard lastDecided != today else { return .spent }
        switch presence {
        case .locked, .asleep, .screenOff: return .away
        case .active, .idle: return .ready
        }
    }

    /// The work day that holds `now` in `zone`.
    public static func day(of now: Date, zone: TimeZone = .current) -> WorkDay {
        WorkDay(containing: now, calendar: .gregorian(in: zone))
    }

    /// The next time the morning hour comes after `now`: when to wake the scheduler.
    public static func nextMorning(after now: Date, hour: Int, zone: TimeZone = .current) -> Date? {
        Calendar.gregorian(in: zone).nextDate(
            after: now, matching: DateComponents(hour: hour, minute: 0, second: 0), matchingPolicy: .nextTime)
    }

    /// The words of the notification; nil when nothing needs the person, which is silence.
    public static func message(needing count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 thing needs you today" : "\(count) things need you today"
    }
}
