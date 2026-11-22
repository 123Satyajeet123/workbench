// Source: built (research K7 §2.4, §6.1: 48 bits of milliseconds and 16 bits of counter in one 64-bit value).

/// A hybrid logical clock stamp: milliseconds since 1970 in the high 48 bits, a counter in the low 16. The top bit
/// is always zero, and the value orders the same as a signed 64-bit integer (Swift `Int64`, SQLite `INTEGER`).
public struct HybridTimestamp: Hashable, Comparable, Sendable, CustomStringConvertible {
    static let counterBits = 16
    public static let maximumMillis: Int64 = Int64.max >> counterBits
    public static let zero = HybridTimestamp(packed: 0)
    public static let max = HybridTimestamp(packed: .max)

    public let rawValue: Int64

    private init(packed: Int64) { rawValue = packed }

    /// Nil when `rawValue` is negative, which no stamp packs to.
    public init?(rawValue: Int64) {
        guard rawValue >= 0 else { return nil }
        self.rawValue = rawValue
    }

    /// Nil when `millis` is outside `0...maximumMillis`.
    public init?(millis: Int64, counter: UInt16) {
        guard (0...Self.maximumMillis).contains(millis) else { return nil }
        rawValue = millis << Self.counterBits | Int64(counter)
    }

    public var millis: Int64 { rawValue >> Self.counterBits }
    public var counter: UInt16 { UInt16(truncatingIfNeeded: rawValue) }

    /// The next stamp: one more in the counter, carrying into the milliseconds when the counter is full. The last
    /// stamp of the range is its own successor.
    var successor: HybridTimestamp {
        let (next, overflow) = rawValue.addingReportingOverflow(1)
        return overflow ? self : HybridTimestamp(packed: next)
    }

    /// The first stamp of a wall-clock millisecond, with the wall clock held inside the range.
    static func start(ofWallMillis wall: Int64) -> HybridTimestamp {
        HybridTimestamp(packed: physical(wall) << counterBits)
    }

    /// A wall-clock reading held inside `0...maximumMillis`.
    static func physical(_ wall: Int64) -> Int64 { Swift.min(Swift.max(wall, 0), maximumMillis) }

    public static func < (lhs: HybridTimestamp, rhs: HybridTimestamp) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "\(millis).\(counter)" }
}
