import CoreGraphics
import Foundation
import Synchronization
import WorkbenchCore

/// Whether the person is at this Mac, read from the platform. No Accessibility call is made. Lock, session, display
/// and idle time are read when asked, so no stale flag is possible after a fast user switch or a missed event. Only
/// system sleep has no read: `note` takes the sleep and wake events that `PowerEvents` delivers. A session the
/// window server does not describe counts as not on the console.
public final class SystemPresence: PresenceSource {
    private let systemAsleep = Mutex(false)

    public init() {}

    public func note(_ event: CaptureEngine.SystemEvent) {
        systemAsleep.withLock { $0 = event == .sleep }
    }

    public func state(idleAfter: TimeInterval) -> PresenceState { reading().state(idleAfter: idleAfter) }

    func reading() -> PresenceReading {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return PresenceReading(
            systemAsleep: systemAsleep.withLock { $0 },
            displayAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0,
            screenLocked: session?["CGSSessionScreenIsLocked"] as? Bool == true,
            sessionOnConsole: session?[kCGSessionOnConsoleKey as String] as? Bool ?? false,
            idleSeconds: CGEventSource.secondsSinceLastEventType(
                .combinedSessionState, eventType: CGEventType(rawValue: ~0)!))
    }
}
