import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

/// The throttle is timed, so each test waits on what happened and not on a fixed delay: a loaded machine slows a test
/// down and does not fail it. A test that must see "nothing more happens" watches for a few periods.
@Suite(.timeLimit(.minutes(1))) struct ChangeThrottleTests {
    private let period = Duration.milliseconds(100)

    private final class Probe: Sendable {
        private let runs = Mutex(0)
        private let holding = Mutex(false)
        var count: Int { runs.withLock { $0 } }

        func hold() { holding.withLock { $0 = true } }
        func release() { holding.withLock { $0 = false } }

        func run() async {
            runs.withLock { $0 += 1 }
            while holding.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(10)) }
        }
    }

    private func throttle(_ probe: Probe) -> ChangeThrottle {
        ChangeThrottle(period: period) { await probe.run() }
    }

    private func waitUntil(_ seconds: Double = 20, _ condition: () -> Bool) async throws -> Bool {
        let end = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < end {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func manyChangesInsideOnePeriodMakeOneRun() async throws {
        let probe = Probe()
        let throttle = throttle(probe)
        for _ in 0..<50 { await throttle.changed() }
        #expect(try await waitUntil { probe.count >= 1 })
        try await Task.sleep(for: period * 5)
        #expect(probe.count == 1)
    }

    @Test func nothingRunsBeforeThePeriodHasPassed() async throws {
        let probe = Probe()
        let long = ChangeThrottle(period: .seconds(30)) { await probe.run() }
        await long.changed()
        try await Task.sleep(for: .milliseconds(300))
        #expect(probe.count == 0)
        await long.stop()
    }

    @Test func aChangeWhileTheActionRunsGetsAnotherRun() async throws {
        let probe = Probe()
        probe.hold()
        let throttle = throttle(probe)
        await throttle.changed()
        #expect(try await waitUntil { probe.count == 1 }, "the first run is going")
        await throttle.changed()
        probe.release()
        #expect(try await waitUntil { probe.count == 2 }, "the change that came during the run is read too")
        try await Task.sleep(for: period * 5)
        #expect(probe.count == 2)
    }

    @Test func aBusySourceStillGetsRunsAndNeverWaitsForQuiet() async throws {
        let probe = Probe()
        let throttle = throttle(probe)
        let end = ContinuousClock.now + .seconds(20)
        while probe.count < 3, ContinuousClock.now < end {
            await throttle.changed()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(probe.count >= 3, "a debounce that waits for quiet would have run none while changes kept coming")
    }

    @Test func stoppingEndsTheWaitWithoutARun() async throws {
        let probe = Probe()
        let throttle = ChangeThrottle(period: .milliseconds(300)) { await probe.run() }
        await throttle.changed()
        await throttle.stop()
        try await Task.sleep(for: .milliseconds(900))
        #expect(probe.count == 0)
    }
}
