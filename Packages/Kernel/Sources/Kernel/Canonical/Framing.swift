// Source: ports judgment-pilot Packages/WorkbenchCore/Sources/WorkbenchCore/Team/Sync/PersonKeys.swift:82-93 (length-
// prefixed parts under a domain tag), with a strict reader added.

/// Length-prefixed parts under a domain tag: a 4-byte big-endian length, then the bytes, for the tag and each part.
/// No two different tag-and-part lists give the same bytes.
public enum Framing {
    public static func bytes(_ domain: String, _ parts: [[UInt8]]) -> [UInt8] {
        ([Array(domain.utf8)] + parts).reduce(into: []) { out, part in
            out += BigEndian.bytes(UInt32(part.count))
            out += part
        }
    }

    /// The parts after `domain`, or nil unless `bytes` is exactly that tag followed by `count` complete parts. It reads
    /// at most `count + 1` parts, whatever the input holds.
    static func parts(of bytes: [UInt8], domain: String, count: Int) -> [[UInt8]]? {
        var parts: [[UInt8]] = []
        var cursor = 0
        for _ in 0...count {
            guard let length = BigEndian.integer(UInt32.self, bytes, at: cursor), let width = Int(exactly: length),
                bytes.count - cursor - 4 >= width
            else { return nil }
            parts.append(Array(bytes[(cursor + 4)..<(cursor + 4 + width)]))
            cursor += 4 + width
        }
        guard cursor == bytes.count, parts.first == Array(domain.utf8) else { return nil }
        return Array(parts.dropFirst())
    }
}

/// Fixed-width big-endian integers, the byte order of every integer the kernel signs.
public enum BigEndian {
    public static func bytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    /// The integer at `offset`, or nil when fewer than its width of bytes remain.
    static func integer<T: FixedWidthInteger>(_ type: T.Type, _ bytes: [UInt8], at offset: Int = 0) -> T? {
        let width = MemoryLayout<T>.size
        guard offset >= 0, bytes.count - offset >= width else { return nil }
        return bytes[offset..<(offset + width)].reduce(T.zero) { $0 << 8 | T($1) }
    }
}
