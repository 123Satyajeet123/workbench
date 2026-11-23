import Foundation

public struct PlanLimits: Codable, Sendable, Equatable {
    public struct Window: Codable, Sendable, Equatable {
        public var used: Double
        public var resetsAt: Date?
        public var isAtLimit: Bool

        public init(used: Double, resetsAt: Date?, isAtLimit: Bool) {
            self.used = used
            self.resetsAt = resetsAt
            self.isAtLimit = isAtLimit
        }
    }

    public var fiveHour: Window?
    public var week: Window?
    public var at: Date

    public init(fiveHour: Window?, week: Window?, at: Date) {
        self.fiveHour = fiveHour
        self.week = week
        self.at = at
    }

    public var windowsAtLimit: [Window] { [fiveHour, week].compactMap { $0 }.filter(\.isAtLimit) }
}
