// Source: built from RFC 8785 §3.2 (no whitespace; ECMAScript string escapes; keys sorted by UTF-16 code units).
// Vectors: cyberphone/json-canonicalization testdata/ (32a48195b9b2).

/// RFC 8785 canonical JSON for `JSONValue`: one byte string per value, the same on every platform.
public enum JCS {
    /// The domain tag of every JCS payload digest.
    public static let payloadTag = "workbench.payload.v2"

    /// SHA-256 over the canonical bytes of `value`, framed under `payloadTag`: the digest a header commits to.
    public static func payloadDigest(_ value: JSONValue) throws(JSONError) -> Digest {
        .framed(payloadTag, [try encode(value)])
    }

    public static func encode(_ value: JSONValue) throws(JSONError) -> [UInt8] {
        var out: [UInt8] = []
        try append(value, to: &out)
        return out
    }

    private static func append(_ value: JSONValue, to out: inout [UInt8]) throws(JSONError) {
        switch value {
        case .null: out += Array("null".utf8)
        case .bool(let flag): out += Array((flag ? "true" : "false").utf8)
        case .integer(let integer): try appendInteger(integer, to: &out)
        case .string(let text): appendString(text, to: &out)
        case .array(let items): try appendArray(items, to: &out)
        case .object(let members): try appendObject(members, to: &out)
        }
    }

    private static func appendInteger(_ integer: Int64, to out: inout [UInt8]) throws(JSONError) {
        guard JSONValue.integerRange.contains(integer) else { throw .integerOutOfRange }
        out += Array(String(integer).utf8)
    }

    private static func appendArray(_ items: [JSONValue], to out: inout [UInt8]) throws(JSONError) {
        out.append(UInt8(ascii: "["))
        for (index, item) in items.enumerated() {
            if index > 0 { out.append(UInt8(ascii: ",")) }
            try append(item, to: &out)
        }
        out.append(UInt8(ascii: "]"))
    }

    private static func appendObject(_ members: [JSONMember], to out: inout [UInt8]) throws(JSONError) {
        let sorted = JSONValue.canonicalOrder(members)
        out.append(UInt8(ascii: "{"))
        for (index, member) in sorted.enumerated() {
            if index > 0 {
                guard !sorted[index - 1].key.utf16.elementsEqual(member.key.utf16) else {
                    throw .duplicateKey(member.key)
                }
                out.append(UInt8(ascii: ","))
            }
            appendString(member.key, to: &out)
            out.append(UInt8(ascii: ":"))
            try append(member.value, to: &out)
        }
        out.append(UInt8(ascii: "}"))
    }

    private static func appendString(_ text: String, to out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        for scalar in text.unicodeScalars {
            out += escaped(scalar) ?? Array(String(scalar).utf8)
        }
        out.append(UInt8(ascii: "\""))
    }

    /// The escape RFC 8785 §3.2.2.2 requires for `scalar`, or nil when it is written as raw UTF-8.
    private static func escaped(_ scalar: Unicode.Scalar) -> [UInt8]? {
        switch scalar {
        case "\"": Array(#"\""#.utf8)
        case "\\": Array(#"\\"#.utf8)
        case "\u{8}": Array(#"\b"#.utf8)
        case "\t": Array(#"\t"#.utf8)
        case "\n": Array(#"\n"#.utf8)
        case "\u{C}": Array(#"\f"#.utf8)
        case "\r": Array(#"\r"#.utf8)
        case "\u{0}"..."\u{1F}": Array(#"\u00"#.utf8) + hexDigits(UInt8(scalar.value))
        default: nil
        }
    }

    private static func hexDigits(_ byte: UInt8) -> [UInt8] {
        let digits = Array("0123456789abcdef".utf8)
        return [digits[Int(byte >> 4)], digits[Int(byte & 0xF)]]
    }
}
