import Foundation
import Synchronization

/// Runs one job again and again while its owner lives. Stopping it, or releasing it, cancels the loop.
nonisolated final class Ticker: Sendable {
    private let loop = Mutex<Task<Void, Never>?>(nil)

    deinit { loop.withLock { $0?.cancel() } }

    /// Runs `job` now, then after each `interval`. Starting again replaces the loop that ran before.
    func start(every interval: Duration = .seconds(60), _ job: @escaping @MainActor () async -> Void) {
        let next = Task {
            while !Task.isCancelled {
                await job()
                try? await Task.sleep(for: interval)
            }
        }
        loop.withLock {
            $0?.cancel()
            $0 = next
        }
    }

    func stop() {
        loop.withLock {
            $0?.cancel()
            $0 = nil
        }
    }
}
