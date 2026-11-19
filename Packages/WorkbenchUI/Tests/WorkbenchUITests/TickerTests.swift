import Foundation
import Testing

@testable import WorkbenchUI

@Suite struct TickerTests {
    @Test func stoppingATickerEndsItsLoop() async throws {
        let ticks = Counter()
        let ticker = Ticker()
        ticker.start(every: .milliseconds(5)) { ticks.value += 1 }
        while ticks.value < 3 { try await Task.sleep(for: .milliseconds(5)) }
        ticker.stop()
        try await Task.sleep(for: .milliseconds(20))
        let stopped = ticks.value
        try await Task.sleep(for: .milliseconds(40))
        #expect(ticks.value == stopped)
    }

    @Test func releasingATickerEndsItsLoop() async throws {
        let ticks = Counter()
        var ticker: Ticker? = Ticker()
        ticker?.start(every: .milliseconds(5)) { ticks.value += 1 }
        while ticks.value < 3 { try await Task.sleep(for: .milliseconds(5)) }
        ticker = nil
        try await Task.sleep(for: .milliseconds(20))
        let released = ticks.value
        try await Task.sleep(for: .milliseconds(40))
        #expect(ticks.value == released)
    }

    private final class Counter { var value = 0 }
}
