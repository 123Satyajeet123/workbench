// Source: ports Actual packages/crdt/src/crdt/timestamp.ts:195-292 (send and receive rules of Kulkarni et al., "Logical
// Physical Clocks", 2014, Fig. 5) with uhlc src/lib.rs:236-317 (carry on overflow; a stamp too far ahead is refused
// and does not move the clock).

/// One device's hybrid logical clock. Every stamp it gives is greater than every stamp it gave or merged before, and
/// stays within `maximumDrift` of the wall clock unless the wall clock goes back. The wall clock is an argument.
public struct HybridClock: Hashable, Sendable {
    public static let maximumDrift: Int64 = 5 * 60 * 1000

    public enum Reception: Hashable, Sendable {
        /// The remote stamp was merged; the value is the clock's new stamp, greater than both.
        case merged(HybridTimestamp)
        /// The remote stamp is more than `maximumDrift` ahead of the wall clock. The clock did not move. The stamp
        /// may be merged once the wall clock reaches `untilWallMillis`.
        case quarantined(untilWallMillis: Int64)
    }

    public private(set) var last: HybridTimestamp

    public init(last: HybridTimestamp = .zero) { self.last = last }

    /// The stamp for a new local event. It never fails.
    public mutating func send(wallMillis: Int64) -> HybridTimestamp {
        last = Swift.max(last.successor, .start(ofWallMillis: wallMillis))
        return last
    }

    /// Merges a stamp from another device, unless it is too far ahead of the wall clock.
    public mutating func receive(_ remote: HybridTimestamp, wallMillis: Int64) -> Reception {
        let quarantineEnd = remote.millis - Self.maximumDrift
        guard HybridTimestamp.physical(wallMillis) >= quarantineEnd else {
            return .quarantined(untilWallMillis: quarantineEnd)
        }
        last = Swift.max(last.successor, remote.successor, .start(ofWallMillis: wallMillis))
        return .merged(last)
    }

    /// True when the clock runs more than `maximumDrift` ahead of the wall clock, as after the wall clock was set back.
    public func isAhead(ofWallMillis wallMillis: Int64) -> Bool {
        last.millis - HybridTimestamp.physical(wallMillis) > Self.maximumDrift
    }
}
