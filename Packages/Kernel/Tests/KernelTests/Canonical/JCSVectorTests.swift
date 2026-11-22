import Foundation
import Kernel
import Testing

/// RFC 8785 vectors from cyberphone/json-canonicalization `testdata/` (32a48195b9b2), copied into `Resources/jcs`.
/// `structures.json` and `values.json` hold floats (`56.0`, `333333333.33333329`, `1E30`), which this closed value
/// type refuses; they are tested as refused, and the non-float part of `values.json` is checked on its own.
@Suite struct JCSVectorTests {
    static let vectorsWithoutFloats = ["arrays", "french", "unicode", "weird"]

    private func resource(_ folder: String, _ name: String, _ ext: String) throws -> [UInt8] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources/jcs/\(folder)"))
        return Array(try Data(contentsOf: url))
    }

    private func hexBytes(_ text: [UInt8]) throws -> [UInt8] {
        try String(decoding: text, as: UTF8.self).split(whereSeparator: \.isWhitespace).map {
            try #require(UInt8($0, radix: 16))
        }
    }

    @Test(arguments: vectorsWithoutFloats)
    func canonicalBytesMatchTheVectorByteForByte(_ name: String) throws {
        let canonical = try JCS.encode(try JSONValue(parsing: try resource("input", name, "json")))
        #expect(canonical == (try hexBytes(try resource("outhex", name, "txt"))))
        #expect(canonical == (try resource("output", name, "json")))
    }

    @Test(arguments: ["structures", "values"])
    func vectorsWithFloatsAreRefused(_ name: String) throws {
        #expect(throws: JSONError.floatNotAllowed) { try JSONValue(parsing: try resource("input", name, "json")) }
    }

    /// values.json without its `numbers` member, and output/values.json without it.
    @Test func theEscapesOfValuesJSONMatch() throws {
        let input = #"{"string": "\u20ac$\u000F\u000aA'\u0042\u0022\u005c\\\"\/", "literals": [null, true, false]}"#
        let expected = #"{"literals":[null,true,false],"string":"€$\u000f\nA'B\"\\\\\"/"}"#
        #expect(try JCS.encode(try JSONValue(parsing: Array(input.utf8))) == Array(expected.utf8))
    }

    /// weird.json: U+1F602 (UTF-16 D83D DE02) sorts before U+FB33, the reverse of UTF-8 and Unicode scalar order.
    @Test func keysSortByUTF16CodeUnits() throws {
        let value = JSONValue.object([.init("\u{FB33}", .integer(1)), .init("\u{1F602}", .integer(2))])
        #expect(try JCS.encode(value) == Array("{\"\u{1F602}\":2,\"\u{FB33}\":1}".utf8))
    }

    /// RFC 8785 Appendix B rows that are integers in the I-JSON range.
    @Test func integersAtTheIJSONLimitsEncodeExactly() throws {
        let rows: [(Int64, String)] = [
            (0, "0"), (-1, "-1"), (9_007_199_254_740_991, "9007199254740991"),
            (-9_007_199_254_740_991, "-9007199254740991"),
        ]
        for (integer, text) in rows {
            #expect(try JCS.encode(.integer(integer)) == Array(text.utf8))
        }
        #expect(try JCS.encode(try JSONValue(parsing: Array("-0".utf8))) == Array("0".utf8))
    }

    @Test func anIntegerPastTheIJSONLimitIsRefused() {
        #expect(throws: JSONError.integerOutOfRange) { try JCS.encode(.integer(9_007_199_254_740_992)) }
        #expect(throws: JSONError.integerOutOfRange) { try JCS.encode(.integer(-9_007_199_254_740_992)) }
        #expect(throws: JSONError.integerOutOfRange) { try JSONValue(parsing: Array("9007199254740992".utf8)) }
    }

    @Test func aDuplicateKeyIsRefusedWhenEncoding() throws {
        let duplicated = JSONValue.object([.init("a", .integer(1)), .init("a", .integer(2))])
        #expect(throws: JSONError.duplicateKey("a")) { try JCS.encode(duplicated) }
        let distinct = JSONValue.object([.init("a", .integer(1)), .init("b", .integer(2))])
        #expect(try JCS.encode(distinct) == Array(#"{"a":1,"b":2}"#.utf8))
    }

    /// structures.json holds one float, `56.0`, whose canonical form is the integer `56` (output/structures.json prints
    /// 56). With that one literal written as `56`, every member matches the vector byte for byte: empty, numeric and
    /// upper- and lower-case keys, `"\n"`, nesting.
    @Test func structuresWithoutItsFloatMatchesTheVector() throws {
        let input = String(decoding: try resource("input", "structures", "json"), as: UTF8.self)
        #expect(input.components(separatedBy: "56.0").count == 2)
        let integerOnly = Array(input.replacingOccurrences(of: "56.0", with: "56").utf8)
        #expect(try JCS.encode(try JSONValue(parsing: integerOnly)) == (try resource("output", "structures", "json")))
    }

    /// RFC 8785 §3.2.2.2 follows ECMAScript `JSON.stringify`: U+2028, U+2029 and U+007F are written raw.
    @Test func lineSeparatorsAndDeleteAreNotEscaped() throws {
        let value = JSONValue.string("\u{2028}\u{2029}\u{7F}")
        #expect(try JCS.encode(value) == [0x22, 0xE2, 0x80, 0xA8, 0xE2, 0x80, 0xA9, 0x7F, 0x22])
    }

    /// RFC 8785 Appendix E: two strings that differ only by NFC and NFD are two values.
    @Test func canonicallyEquivalentStringsAreDifferentValues() {
        #expect(JSONValue.string("\u{C5}") != JSONValue.string("A\u{30A}"))
        #expect(JSONValue.string("\u{C5}") == JSONValue.string("\u{C5}"))
    }

    /// The digest a header commits to, pinned and computed apart from this code (Python hashlib over the same framing).
    @Test func thePayloadDigestIsPinned() throws {
        let payload = JSONValue.object([.init("kind", .string("commitment")), .init("due", .string("2026-11-27"))])
        #expect(JCS.payloadTag == "workbench.payload.v2")
        #expect(
            try JCS.payloadDigest(payload).description
                == "bd8f54885787db87601275c5d246f6c723b98ae227bee3d7dde88aedffa6c59d")
    }

    /// RFC 8785 Appendix E: strings are never normalized, so NFC and NFD keys stay two keys, in UTF-16 order.
    @Test func canonicallyEquivalentKeysStayDistinct() throws {
        let value = try JSONValue(parsing: Array(#"{"\u00c5":1,"A\u030a":2}"#.utf8))
        #expect(try JCS.encode(value) == Array("{\"A\u{030A}\":2,\"\u{00C5}\":1}".utf8))
    }
}
