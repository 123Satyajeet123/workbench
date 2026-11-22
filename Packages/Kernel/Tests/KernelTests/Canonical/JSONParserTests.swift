import Kernel
import Testing

/// The strict parser behind "re-encode and compare" (research K7 §3.1 pitfall 5). Each guard is tested both ways.
@Suite struct JSONParserTests {
    private func parse(_ text: String) throws(JSONError) -> JSONValue { try JSONValue(parsing: Array(text.utf8)) }

    @Test func everyKindOfValueParses() throws {
        let value = try parse(#" { "a" : [ null , true , false , -12 , "x" ] , "b" : { } } "#)
        let expected = JSONValue.object([
            .init("a", .array([.null, .bool(true), .bool(false), .integer(-12), .string("x")])),
            .init("b", .object([])),
        ])
        #expect(value == expected)
    }

    @Test func aFractionOrAnExponentIsRefused() throws {
        for text in ["1.0", "1e3", "1E3", "-0.5", "[2e-3]"] {
            #expect(throws: JSONError.floatNotAllowed) { try parse(text) }
        }
        #expect(try parse("10") == .integer(10))
    }

    @Test func aDuplicateKeyIsRefused() throws {
        #expect(throws: JSONError.duplicateKey("a")) { try parse(#"{"a":1,"a":1}"#) }
        #expect(throws: JSONError.duplicateKey("a")) { try parse(#"{"a":1,"\u0061":2}"#) }
        #expect(try parse(#"{"a":1,"b":1}"#) == .object([.init("a", .integer(1)), .init("b", .integer(1))]))
    }

    @Test func aLoneSurrogateIsRefused() throws {
        for text in [#""\ud83d""#, #""\ude02""#, #""\ud83dx""#, #""\ud83d\u0041""#] {
            #expect(throws: JSONError.loneSurrogate) { try parse(text) }
        }
        #expect(try parse(#""😂""#) == .string("\u{1F602}"))
    }

    @Test func aRawControlCharacterIsRefusedAndAnEscapedOneParses() throws {
        #expect(throws: JSONError.controlCharacter) { try parse("\"a\u{1}b\"") }
        #expect(throws: JSONError.controlCharacter) { try parse("\"a\nb\"") }
        #expect(try parse(#""a\u0001b""#) == .string("a\u{1}b"))
    }

    @Test func invalidUTF8IsRefused() throws {
        #expect(throws: JSONError.invalidUTF8) { try JSONValue(parsing: [0x22, 0xC3, 0x28, 0x22]) }
        #expect(throws: JSONError.invalidUTF8) { try JSONValue(parsing: [0x22, 0xED, 0xA0, 0x80, 0x22]) }
        #expect(try JSONValue(parsing: [0x22, 0xC3, 0xA9, 0x22]) == .string("é"))
    }

    @Test func malformedTextIsRefusedWithItsOffset() {
        #expect(throws: JSONError.invalidSyntax(at: 0)) { try parse("") }
        #expect(throws: JSONError.invalidSyntax(at: 1)) { try parse("01") }
        #expect(throws: JSONError.invalidSyntax(at: 1)) { try parse("-") }
        #expect(throws: JSONError.invalidSyntax(at: 5)) { try parse("[1,2,]") }
        #expect(throws: JSONError.invalidSyntax(at: 0)) { try parse("nul") }
        #expect(throws: JSONError.invalidSyntax(at: 2)) { try parse(#""\x""#) }
        #expect(throws: JSONError.invalidSyntax(at: 0)) { try parse("\u{FEFF}1") }
        #expect(throws: JSONError.invalidSyntax(at: 7)) { try parse(#"{"a":1 "b":2}"#) }
    }

    @Test func contentAfterTheValueIsRefused() throws {
        #expect(throws: JSONError.trailingContent(at: 2)) { try parse("1 2") }
        #expect(try parse(" 1 \n\t\r") == .integer(1))
    }

    @Test func nestingDeeperThanTheLimitIsRefused() throws {
        let limit = JSONValue.maximumDepth
        let atLimit = String(repeating: "[", count: limit) + String(repeating: "]", count: limit)
        #expect(throws: Never.self) { try parse(atLimit) }
        let tooDeep = "[" + atLimit + "]"
        #expect(throws: JSONError.tooDeep) { try parse(tooDeep) }
    }
}
