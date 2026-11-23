import Foundation
import Synchronization

nonisolated final class Ticker: Sendable {
    private let loop = Mutex<Task<Void, Never>?>(nil)

    deinit { loop.withLock { $0?.cancel() } }

    func start(
        every interval: Duration = .seconds(60), waitingFirst: Bool = false,
        _ job: @escaping @MainActor () async -> Void
    ) {
        let next = Task {
            if waitingFirst { try? await Task.sleep(for: interval) }
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
