import Kernel
import PropertyBased
import Testing

/// Review 1 F1: a name has one equality everywhere. Equality, order, hashing, label ids and access checks agree on
/// every spelling, NFC or NFD.
@Suite struct IdentifierTests {
    @Test func emptyTextAndControlCharactersAreRefused() throws {
        #expect(throws: IdentifierError.empty) { try PersonID("") }
        #expect(throws: IdentifierError.controlCharacter) { try PersonID("dev\n") }
        #expect(throws: IdentifierError.controlCharacter) { try SourceClass("a\u{85}b") }
        #expect(try PersonID("Zo\u{EB}").rawValue == "Zo\u{EB}")
    }

    @Test func aNameIsStoredInNFC() throws {
        let decomposed = try PersonID("Zoe\u{308}")
        #expect(Array(decomposed.rawValue.utf8) == Array("Zo\u{EB}".utf8))
        #expect(decomposed == (try PersonID("Zo\u{EB}")))
        #expect(Set([decomposed, try PersonID("Zo\u{EB}")]).count == 1)
    }

    @Test func twoSpellingsOfOneOwnerAndKeyNameOneSource() throws {
        let composed = Source(owner: try PersonID("Zo\u{EB}"), key: try SourceKey("caf\u{E9}"))
        let decomposed = Source(owner: try PersonID("Zoe\u{308}"), key: try SourceKey("cafe\u{301}"))
        #expect(composed.id == decomposed.id)
        #expect(Label(source: composed.id).id == Label(source: decomposed.id).id)
    }

    @Test func namesSpelledApartAreOneNameForEveryCheck() async { await NameLaws.oneEqualityEverywhere(.kernel) }

    @Test(.shrinking(false)) func oneEqualityCatchesPlantedBreak() async {
        await expectPlantedBreakCaught("names keep their raw text and compare with String ==") {
            await NameLaws.oneEqualityEverywhere(.rawText)
        }
    }
}

enum NameLaws {
    /// Letters with an NFC and an NFD spelling, and letters with one.
    static let pieces: [(String, String)] = [
        ("\u{E9}", "e\u{301}"), ("\u{C5}", "A\u{30A}"), ("\u{F6}", "o\u{308}"), ("a", "a"), ("b", "b"),
    ]

    /// Two names: the same letters spelled independently (so often one NFC and one NFD), or other letters.
    static let pairs = Generator(run: { rng in
        let letters = (0..<Int.random(in: 1...4, using: &rng)).map { _ in Int.random(in: 0..<pieces.count, using: &rng)
        }
        let other = Bool.random(using: &rng) ? letters : letters.map { ($0 + 1) % pieces.count }
        func spell(_ indices: [Int], _ rng: inout any SeededRandomNumberGenerator) -> String {
            indices.map { Bool.random(using: &rng) ? pieces[$0].0 : pieces[$0].1 }.joined()
        }
        return (spell(letters, &rng), spell(other, &rng))
    })

    /// Equal names have equal label ids and read each other's grants; unequal names differ in both; the order
    /// agrees with equality.
    static func oneEqualityEverywhere(_ names: NameAlgebra) async {
        await propertyCheck(count: 300, input: pairs) { a, b in
            let same = names.same(a, b)
            #expect(same == (names.labelID(a) == names.labelID(b)))
            #expect(same == names.reads(a, b))
            #expect(same ? !names.before(a, b) && !names.before(b, a) : names.before(a, b) != names.before(b, a))
        }
    }
}

/// How names behave: `kernel`, or a planted break.
struct NameAlgebra: Sendable {
    var same: @Sendable (String, String) -> Bool
    var before: @Sendable (String, String) -> Bool
    var labelID: @Sendable (String) -> [UInt8]
    /// Whether a roster member named `a` reads a source granted to a person named `b`.
    var reads: @Sendable (String, String) -> Bool

    private static let owner = person("owner")
    private static let place = source(owner, "place")

    static let kernel = NameAlgebra(
        same: { sourceClass($0) == sourceClass($1) },
        before: { sourceClass($0) < sourceClass($1) },
        labelID: { Label(source: place.id, classes: [sourceClass($0)]).id.bytes },
        reads: { member, granted in
            let grant = Grant(signer: owner, source: place, readers: [person(granted)], epoch: 0)
            return !Label(source: place.id).readers(grants: Grants([grant]), roster: Roster(members: [person(member)]))
                .isEmpty
        })

    /// The identifiers before review 1: raw text, Swift `String ==`, UTF-16 order, ids over the raw bytes.
    static let rawText = NameAlgebra(
        same: { $0 == $1 },
        before: { $0.utf16.lexicographicallyPrecedes($1.utf16) },
        labelID: { Digest.sha256(Array($0.utf8)).bytes },
        reads: { $0 == $1 })
}
