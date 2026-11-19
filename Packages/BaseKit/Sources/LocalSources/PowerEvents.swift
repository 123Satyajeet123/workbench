import AppKit
import WorkbenchCore

/// Sleep and wake of the Mac, delivered on the main queue until the value is released.
@MainActor
public final class PowerEvents {
    private var observers: [NSObjectProtocol] = []

    public init(handler: @escaping @MainActor (CaptureEngine.SystemEvent) -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        for (name, event) in [
            (NSWorkspace.willSleepNotification, CaptureEngine.SystemEvent.sleep),
            (NSWorkspace.didWakeNotification, .wake),
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { handler(event) }
                })
        }
    }

    public func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
    }
}
