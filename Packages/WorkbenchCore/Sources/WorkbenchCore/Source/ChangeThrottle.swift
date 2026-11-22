import Foundation

/// Turns many change events into few runs. The first change starts a wait of `period`; every change inside the wait
/// joins the run that follows it. A change that comes while the action runs gets another run after a new wait. So a
/// change is acted on within `period` plus one run, however busy the source is: a trailing debounce, which waits for
/// quiet, could put off an erasure for as long as a chat stays busy.
public actor ChangeThrottle {
    private let period: Duration
    private let action: @Sendable () async -> Void
    private var firstUnhandledChange: ContinuousClock.Instant?
    private var worker: Task<Void, Never>?

    public init(period: Duration, action: @escaping @Sendable () async -> Void) {
        self.period = period
        self.action = action
    }

    public func changed() {
        if firstUnhandledChange == nil { firstUnhandledChange = .now }
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    /// Ends the wait and any run that has not started. A run that has started finishes.
    public func stop() {
        worker?.cancel()
        worker = nil
        firstUnhandledChange = nil
    }

    private func drain() async {
        while let first = firstUnhandledChange {
            try? await Task.sleep(until: first + period, clock: .continuous)
            guard !Task.isCancelled else { return }
            firstUnhandledChange = nil
            await action()
        }
        worker = nil
    }
}
