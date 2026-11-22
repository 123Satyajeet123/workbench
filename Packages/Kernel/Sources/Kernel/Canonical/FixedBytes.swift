// Source: built.

import Crypto

/// A value made of a fixed number of bytes, ordered byte by byte, never as text.
public protocol FixedBytes: Hashable, Comparable, Sendable, CustomStringConvertible {
    static var count: Int { get }
    var bytes: [UInt8] { get }
    /// Nil unless `bytes` has exactly `count` bytes.
    init?(bytes: [UInt8])
}

extension FixedBytes {
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.bytes.lexicographicallyPrecedes(rhs.bytes) }

    public var description: String { bytes.map { String($0 >> 4, radix: 16) + String($0 & 0xF, radix: 16) }.joined() }
}

/// A SHA-256 digest: event ids, backlinks and body commitments.
public struct Digest: FixedBytes {
    public static let count = 32
    public static let zero = Digest(sha256Output: Array(repeating: 0, count: count))

    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.count else { return nil }
        self.bytes = bytes
    }

    private init(sha256Output: [UInt8]) { bytes = sha256Output }

    public static func sha256(_ data: [UInt8]) -> Digest { Digest(sha256Output: Array(SHA256.hash(data: data))) }

    /// SHA-256 over `parts` framed under `domain`.
    public static func framed(_ domain: String, _ parts: [[UInt8]]) -> Digest { sha256(Framing.bytes(domain, parts)) }
}

/// The id of a signed event: SHA-256 of its signed bytes, so a second signature over the same bytes is the same event.
public typealias EventID = Digest
