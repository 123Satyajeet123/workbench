import Foundation

/// Whether the person is at the Mac. One signal for every capture loop: a loop that polls the screen reads nothing
/// unless the state is `active`.
public enum PresenceState: Sendable, Equatable {
    case active, idle, locked, asleep, screenOff
}

/// The platform facts behind a `PresenceState`. Pure: the platform fills it, the tests drive it.
public struct PresenceReading: Sendable, Equatable {
    public var systemAsleep: Bool
    public var displayAsleep: Bool
    public var screenLocked: Bool
    /// False while another user's session is in front (fast user switching).
    public var sessionOnConsole: Bool
    public var idleSeconds: TimeInterval

    public init(
        systemAsleep: Bool = false, displayAsleep: Bool = false, screenLocked: Bool = false,
        sessionOnConsole: Bool = true, idleSeconds: TimeInterval = 0
    ) {
        self.systemAsleep = systemAsleep
        self.displayAsleep = displayAsleep
        self.screenLocked = screenLocked
        self.sessionOnConsole = sessionOnConsole
        self.idleSeconds = idleSeconds
    }

    /// The most restrictive fact wins, because any one of them means nobody is reading the screen: a wrong "away"
    /// costs one tick of capture, a wrong "active" reads a locked screen. Idle time does not rule out a lock: a locked
    /// screen right after a mouse move has no idle time.
    public func state(idleAfter: TimeInterval) -> PresenceState {
        if systemAsleep { return .asleep }
        if displayAsleep { return .screenOff }
        if screenLocked || !sessionOnConsole { return .locked }
        return idleSeconds >= idleAfter ? .idle : .active
    }
}

/// Where a loop asks whether the person is here. The platform's answer is `SystemPresence`.
public protocol PresenceSource: Sendable {
    func state(idleAfter: TimeInterval) -> PresenceState
}
