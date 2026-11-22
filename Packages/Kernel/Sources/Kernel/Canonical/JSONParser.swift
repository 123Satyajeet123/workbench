// Source: built from RFC 8259 §2-7 (grammar) and RFC 7493 §2 (I-JSON: UTF-8 only, no lone surrogates, no duplicate
// keys, integers within ±(2^53 - 1)), with the nesting limit of p2panda p2panda-core/src/operation/any.rs:195-207.

extension JSONValue {
    /// Parses `bytes` as one JSON value in this closed type. Anything outside it is refused: floats, integers outside
    /// the I-JSON range, duplicate keys, lone surrogates, raw control characters, invalid UTF-8, nesting deeper than
    /// `maximumDepth`, and bytes after the value.
    public init(parsing bytes: [UInt8]) throws(JSONError) {
        var parser = JSONParser(bytes)
        self = try parser.document()
    }
}

private struct JSONParser {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    mutating func document() throws(JSONError) -> JSONValue {
        skipWhitespace()
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw .trailingContent(at: index) }
        return value
    }

    private mutating func parseValue(depth: Int) throws(JSONError) -> JSONValue {
        guard let byte = current else { throw .invalidSyntax(at: index) }
        switch byte {
        case UInt8(ascii: "{"): return .object(try parseObject(depth: depth + 1))
        case UInt8(ascii: "["): return .array(try parseArray(depth: depth + 1))
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): return try literal("true", .bool(true))
        case UInt8(ascii: "f"): return try literal("false", .bool(false))
        case UInt8(ascii: "n"): return try literal("null", .null)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .integer(try parseInteger())
        default: throw .invalidSyntax(at: index)
        }
    }

    private mutating func parseObject(depth: Int) throws(JSONError) -> [JSONMember] {
        guard depth <= JSONValue.maximumDepth else { throw .tooDeep }
        index += 1
        skipWhitespace()
        var members: [JSONMember] = []
        var keys = Set<[UInt16]>()
        guard current != UInt8(ascii: "}") else {
            index += 1
            return members
        }
        repeat {
            skipWhitespace()
            guard current == UInt8(ascii: "\"") else { throw .invalidSyntax(at: index) }
            let key = try parseString()
            guard keys.insert(Array(key.utf16)).inserted else { throw .duplicateKey(key) }
            skipWhitespace()
            try expect(":")
            skipWhitespace()
            members.append(JSONMember(key, try parseValue(depth: depth)))
            skipWhitespace()
        } while try continues(closingWith: "}")
        return members
    }

    private mutating func parseArray(depth: Int) throws(JSONError) -> [JSONValue] {
        guard depth <= JSONValue.maximumDepth else { throw .tooDeep }
        index += 1
        skipWhitespace()
        var items: [JSONValue] = []
        guard current != UInt8(ascii: "]") else {
            index += 1
            return items
        }
        repeat {
            skipWhitespace()
            items.append(try parseValue(depth: depth))
            skipWhitespace()
        } while try continues(closingWith: "]")
        return items
    }

    /// Consumes a comma (true: another element follows) or the closing bracket (false).
    private mutating func continues(closingWith closer: Unicode.Scalar) throws(JSONError) -> Bool {
        switch current {
        case UInt8(ascii: ","):
            index += 1
            return true
        case UInt8(ascii: closer):
            index += 1
            return false
        default:
            throw .invalidSyntax(at: index)
        }
    }

    private mutating func parseInteger() throws(JSONError) -> Int64 {
        let negative = current == UInt8(ascii: "-")
        if negative { index += 1 }
        guard let first = digit(current) else { throw .invalidSyntax(at: index) }
        index += 1
        var magnitude = first
        while let next = digit(current) {
            guard first != 0 else { throw .invalidSyntax(at: index) }
            magnitude = magnitude * 10 + next
            guard magnitude <= JSONValue.maximumInteger else { throw .integerOutOfRange }
            index += 1
        }
        guard ![UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E")].contains(current) else {
            throw .floatNotAllowed
        }
        return negative ? -magnitude : magnitude
    }

    private mutating func parseString() throws(JSONError) -> String {
        index += 1
        var utf8: [UInt8] = []
        while true {
            guard let byte = current else { throw .invalidSyntax(at: index) }
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                guard let text = String(validating: utf8, as: UTF8.self) else { throw .invalidUTF8 }
                return text
            case UInt8(ascii: "\\"):
                utf8 += Array(String(try parseEscape()).utf8)
            case 0..<0x20:
                throw .controlCharacter
            default:
                utf8.append(byte)
            }
        }
    }

    /// The scalar of one escape; `index` is just past the backslash.
    private mutating func parseEscape() throws(JSONError) -> Unicode.Scalar {
        guard let byte = current else { throw .invalidSyntax(at: index) }
        index += 1
        switch byte {
        case UInt8(ascii: "\""): return "\""
        case UInt8(ascii: "\\"): return "\\"
        case UInt8(ascii: "/"): return "/"
        case UInt8(ascii: "b"): return "\u{8}"
        case UInt8(ascii: "f"): return "\u{C}"
        case UInt8(ascii: "n"): return "\n"
        case UInt8(ascii: "r"): return "\r"
        case UInt8(ascii: "t"): return "\t"
        case UInt8(ascii: "u"): return try parseUnicodeEscape()
        default: throw .invalidSyntax(at: index - 1)
        }
    }

    /// A `\uXXXX` escape, or a surrogate pair of two; `index` is just past the `u`.
    private mutating func parseUnicodeEscape() throws(JSONError) -> Unicode.Scalar {
        let lead = try parseHexUnit()
        if let scalar = Unicode.Scalar(lead) { return scalar }
        guard UTF16.isLeadSurrogate(lead), current == UInt8(ascii: "\\"),
            bytes.dropFirst(index + 1).first == UInt8(ascii: "u")
        else { throw .loneSurrogate }
        index += 2
        let trail = try parseHexUnit()
        guard UTF16.isTrailSurrogate(trail) else { throw .loneSurrogate }
        return UTF16.decode(UTF16.EncodedScalar([lead, trail]))
    }

    private mutating func parseHexUnit() throws(JSONError) -> UInt16 {
        var unit: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = current, let value = hexValue(byte) else { throw .invalidSyntax(at: index) }
            unit = unit << 4 | value
            index += 1
        }
        return unit
    }

    private mutating func literal(_ word: String, _ value: JSONValue) throws(JSONError) -> JSONValue {
        let text = Array(word.utf8)
        guard bytes[index...].starts(with: text) else { throw .invalidSyntax(at: index) }
        index += text.count
        return value
    }

    private mutating func expect(_ scalar: Unicode.Scalar) throws(JSONError) {
        guard current == UInt8(ascii: scalar) else { throw .invalidSyntax(at: index) }
        index += 1
    }

    private mutating func skipWhitespace() {
        while let byte = current, [0x20, 0x09, 0x0A, 0x0D].contains(byte) { index += 1 }
    }

    private func digit(_ byte: UInt8?) -> Int64? {
        guard let byte, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
        return Int64(byte - UInt8(ascii: "0"))
    }

    private func hexValue(_ byte: UInt8) -> UInt16? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt16(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt16(byte - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A")...UInt8(ascii: "F"): UInt16(byte - UInt8(ascii: "A") + 10)
        default: nil
        }
    }
}
