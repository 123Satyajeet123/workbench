// Source: built (research 56 §1: resolved UTC times only; research E-R1 §4.2 defect 1).

import Foundation
import Kernel

/// A resolved moment: whole milliseconds since 1970-01-01 00:00:00 UTC. A time label such as "Today at 18:20" is not
/// an instant; a reader resolves it before a line is made, or gives no time.
public struct UTCInstant: Hashable, Comparable, Sendable {
    public let milliseconds: Int64

    public init(milliseconds: Int64) { self.milliseconds = milliseconds }

    /// The date rounded to the nearest millisecond.
    public init(_ date: Date) { milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    public static func < (lhs: UTCInstant, rhs: UTCInstant) -> Bool { lhs.milliseconds < rhs.milliseconds }

    var bytes: [UInt8] { BigEndian.bytes(milliseconds) }
}

extension Duration {
    /// The duration in whole milliseconds, rounded toward zero.
    var milliseconds: Int64 { components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000 }
}
