import Foundation
import Kernel
import PropertyBased
import Testing

/// Canonical-bytes properties over random values built from characters that break naive encoders: both orders of
/// UTF-16 and scalar sorting, NFC and NFD forms, quotes, backslashes and control characters.
@Suite struct JCSLawTests {
    @Test func parsingTheBytesGivesTheValueBack() async { await JCSLaws.parsingTheBytesGivesTheValueBack(.kernel) }

    @Test(.shrinking(false)) func parsingTheBytesCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("strings are normalized to NFC before encoding (RFC 8785 Appendix E)") {
            await JCSLaws.parsingTheBytesGivesTheValueBack(.normalizesToNFC)
        }
    }

    @Test func memberOrderNeverChangesTheBytes() async { await JCSLaws.memberOrderNeverChangesTheBytes(.kernel) }

    @Test(.shrinking(false)) func memberOrderCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("Foundation JSONSerialization with sorted keys (research K7 §3.1 pitfall 4)") {
            await JCSLaws.memberOrderNeverChangesTheBytes(.foundationSortedKeys)
        }
    }
}

enum JCSLaws {
    static let alphabet = [
        "a", "B", "1", "10", "\u{E9}", "e\u{301}", "\u{FB33}", "\u{1F602}", "\"", "\\", "\n", "\u{1}", "\u{7F}", "/",
        "\u{2028}", "\u{20AC}",
    ]

    static func randomString(_ rng: inout any SeededRandomNumberGenerator) -> String {
        (0..<Int.random(in: 0...4, using: &rng)).map { _ in alphabet.randomElement(using: &rng) ?? "" }.joined()
    }

    static func randomValue(depth: Int, _ rng: inout any SeededRandomNumberGenerator) -> JSONValue {
        let kind = Int.random(in: 0...(depth > 0 ? 5 : 3), using: &rng)
        switch kind {
        case 0: return .null
        case 1: return .bool(Bool.random(using: &rng))
        case 2: return .integer(Int64.random(in: -JSONValue.maximumInteger...JSONValue.maximumInteger, using: &rng))
        case 3: return .string(randomString(&rng))
        case 4: return .array((0..<Int.random(in: 0...3, using: &rng)).map { _ in randomValue(depth: depth - 1, &rng) })
        default: return .object(uniqueMembers(depth: depth - 1, &rng))
        }
    }

    static func uniqueMembers(depth: Int, _ rng: inout any SeededRandomNumberGenerator) -> [JSONMember] {
        var seen = Set<[UInt16]>()
        return (0..<Int.random(in: 0...4, using: &rng)).compactMap { _ in
            let key = randomString(&rng)
            guard seen.insert(Array(key.utf16)).inserted else { return nil }
            return JSONMember(key, randomValue(depth: depth, &rng))
        }
    }

    static let value = Generator(run: { rng in randomValue(depth: 3, &rng) })

    static let shuffledObject = Generator(run: { rng in
        let members = uniqueMembers(depth: 1, &rng)
        return (members, members.shuffled(using: &rng))
    })

    /// Decoding the canonical bytes gives back exactly the value encoded, string by string and scalar by scalar.
    static func parsingTheBytesGivesTheValueBack(_ canonical: Canonicalizer) async {
        await propertyCheck(count: 300, input: value) { value in
            let bytes = try canonical.encode(value)
            #expect(try JSONValue(parsing: bytes) == value)
        }
    }

    /// The order members were given in never changes the bytes, and keys come out in UTF-16 code unit order.
    static func memberOrderNeverChangesTheBytes(_ canonical: Canonicalizer) async {
        await propertyCheck(count: 300, input: shuffledObject) { members, shuffled in
            let bytes = try canonical.encode(.object(members))
            #expect(try canonical.encode(.object(shuffled)) == bytes)
            guard case .object(let decoded) = try JSONValue(parsing: bytes) else {
                Issue.record("an object did not encode as an object")
                return
            }
            let keys = decoded.map { Array($0.key.utf16) }
            #expect(keys == keys.sorted { $0.lexicographicallyPrecedes($1) })
            #expect(decoded.count == members.count)
        }
    }
}

/// A canonical encoder: `kernel`, or a planted break.
struct Canonicalizer: Sendable {
    var encode: @Sendable (JSONValue) throws -> [UInt8]

    static let kernel = Canonicalizer(encode: { try JCS.encode($0) })

    static let normalizesToNFC = Canonicalizer(encode: { try JCS.encode(nfc($0)) })

    static let foundationSortedKeys = Canonicalizer(encode: { value in
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
        return Array(try JSONSerialization.data(withJSONObject: foundationObject(value), options: options))
    })

    private static func nfc(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let text): .string(text.precomposedStringWithCanonicalMapping)
        case .array(let items): .array(items.map(nfc))
        case .object(let members):
            .object(members.map { JSONMember($0.key.precomposedStringWithCanonicalMapping, nfc($0.value)) })
        case .null, .bool, .integer: value
        }
    }

    private static func foundationObject(_ value: JSONValue) -> Any {
        switch value {
        case .null: NSNull()
        case .bool(let flag): flag
        case .integer(let integer): integer
        case .string(let text): text
        case .array(let items): items.map(foundationObject)
        case .object(let members):
            Dictionary(members.map { ($0.key, foundationObject($0.value)) }, uniquingKeysWith: { first, _ in first })
        }
    }
}
