import Foundation

/// Whether an outbound machine finds startups by itself once a week.
struct WeeklySearch: Codable, Equatable {
    static let interval: TimeInterval = 7 * 86_400

    var isOn = false

    func isDue(at now: Date, lastRan: Date?) -> Bool {
        guard isOn else { return false }
        guard let lastRan else { return true }
        return now.timeIntervalSince(lastRan) >= Self.interval
    }
}
