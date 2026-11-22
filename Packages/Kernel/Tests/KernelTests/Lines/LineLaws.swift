import Foundation
import Kernel
import PropertyBased
import Testing

@testable import Lines

/// The identity functions a law checks. `lines` is the code under test; every other value is a planted break, a
/// wrong implementation that one law must catch.
struct LineIdentity: Sendable {
    /// The id of a line with this entity, text and reader version.
    var id: @Sendable (EntitySpec, String, String) -> LineID
    /// The ids of one read of a screen container, in reading order.
    var screen: @Sendable (String, [String]) -> [LineID]
    var normalize: @Sendable (String) -> String
    /// The id of a calendar line whose occurrence a reader resolved in this time zone.
    var calendar: @Sendable (Date, TimeZone) -> LineID
    var view: @Sendable (String, [LineID]) -> ViewID

    static let lines = LineIdentity(
        id: { spec, text, version in
            fixture { try Line(entity: spec.key(text: text), text: text, readerVersion: version).id }
        },
        screen: { container, texts in
            fixture { try Line.screen(container: container, texts: texts, readerVersion: "r1").map(\.id) }
        },
        normalize: IdentityText.normalize,
        calendar: { date, _ in
            let entity = fixture { try EntityKey.calendar(externalID: "e1", occurrence: UTCInstant(date)) }
            return Line(entity: entity, text: "call", readerVersion: "r1").id
        },
        view: { ViewID(container: $0, lines: $1) }
    )

    /// SHA-256 over the parts framed under `tag`, read as a line id.
    static func digest(_ tag: String, _ parts: [[UInt8]]) -> LineID {
        LineID(bytes: Digest.sha256(Framing.bytes(tag, parts)).bytes)!
    }

    /// The id with the content hashed from `content(text)` in place of the identity text.
    static func withContent(_ content: @escaping @Sendable (String) -> String) -> LineIdentity {
        var identity = lines
        identity.id = { spec, text, _ in
            digest("workbench.line.v1", [fixture { try spec.key(text: text) }.bytes, Array(content(text).utf8)])
        }
        return identity
    }

    static let readTimeInHash: LineIdentity = {
        var identity = lines
        identity.id = { spec, text, version in
            let id = lines.id(spec, text, version)
            return digest("read", [id.bytes, BigEndian.bytes(UInt64.random(in: 0...UInt64.max))])
        }
        return identity
    }()

    static let rawTextBytes = withContent { $0 }

    static let nfcWithoutSpacingRules = withContent { $0.precomposedStringWithCanonicalMapping }

    static let lowercasesText = withContent { IdentityText.normalize($0).lowercased() }

    static let stripsJoiners = withContent {
        String(
            String.UnicodeScalarView(
                IdentityText.normalize($0).unicodeScalars.filter { $0 != "\u{200D}" && $0 != "\u{200C}" }))
    }

    static let readerVersionInHash: LineIdentity = {
        var identity = lines
        identity.id = { spec, text, version in
            let id = lines.id(spec, text, version)
            return digest("version", [id.bytes, Array(version.utf8)])
        }
        return identity
    }()

    static let concatenatedEntityFields: LineIdentity = {
        var identity = lines
        identity.id = { spec, text, _ in
            digest("workbench.line.v1", [Array((spec.concatenated + IdentityText.normalize(text)).utf8)])
        }
        return identity
    }()

    /// NFC first, then the invisible characters and spaces: a mark after a removed character stays uncombined.
    static let normalizesBeforeStripping: LineIdentity = {
        var identity = lines
        identity.normalize = { stripThenFold($0.precomposedStringWithCanonicalMapping) }
        return identity
    }()

    /// The invisible characters removed and white space folded, with no NFC step.
    static func stripThenFold(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { !IdentityText.isInvisible($0.value) }
        return String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func screenIDs(_ container: String, _ texts: [String], ordinal: (Int, Int) -> Int) throws -> [LineID] {
        var seen: [ContentHash: Int] = [:]
        return try texts.enumerated().map { position, text in
            let content = ContentHash(text: text)
            let occurrence = seen[content, default: 0]
            seen[content] = occurrence + 1
            let key = try EntityKey.screen(
                container: container, content: content, ordinal: UInt32(ordinal(position, occurrence)))
            return Line(entity: key, text: text, readerVersion: "r1").id
        }
    }

    static let noDuplicateOrdinal: LineIdentity = {
        var identity = lines
        identity.screen = { container, texts in fixture { try screenIDs(container, texts) { _, _ in 0 } } }
        return identity
    }()

    /// The ordinal is the place in the read (screenpipe's defect 2, research E-R1 §4.2).
    static let positionOrdinal: LineIdentity = {
        var identity = lines
        identity.screen = { container, texts in
            fixture { try screenIDs(container, texts) { position, _ in position } }
        }
        return identity
    }()

    /// The occurrence written as local wall time, as a label like "Today at 18:20" is (E-R1 §4.2 defect 1).
    static let localWallTime: LineIdentity = {
        var identity = lines
        identity.calendar = { date, zone in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return digest("workbench.line.v1", [Array(("e1" + formatter.string(from: date)).utf8)])
        }
        return identity
    }()

    static let sortedView: LineIdentity = {
        var identity = lines
        identity.view = { ViewID(container: $0, lines: $1.sorted()) }
        return identity
    }()
}

enum LineLaws {
    static let cases = 300
    static let entity = EntitySpec.direct(chat: "91@s.whatsapp.net", fromMe: false, stanza: "3EB0", occurrence: 0)

    /// Two lines made apart from the same entity, text and reader version have one id.
    static func sameInputsGiveTheSameID(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.spacedPair) { input in
            let (text, _) = input
            #expect(identity.id(entity, text, "r1") == (identity.id(entity, text, "r1")))
        }
    }

    /// Canonically equal spellings (NFC, NFD, mixed) of one text have one id.
    static func canonicalSpellingsGiveTheSameID(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.canonicalPair) { input in
            let (a, b) = input
            #expect(identity.id(entity, a, "r1") == (identity.id(entity, b, "r1")))
        }
    }

    /// Runs of white space, white space at the ends, and invisible format characters do not change the id.
    static func spacingAndInvisibleCharactersKeepTheID(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.spacedPair) { input in
            let (clean, messy) = input
            #expect(identity.id(entity, clean, "r1") == (identity.id(entity, messy, "r1")))
        }
    }

    /// Two different entity keys never share an id for one text, also when they hold the same characters.
    static func anyChangeInTheEntityChangesTheID(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.changedEntity) { input in
            let (a, b, text) = input
            #expect(identity.id(a, text, "r1") != (identity.id(b, text, "r1")))
        }
    }

    /// A change of case, a joiner inside a conjunct, or another word gives another id.
    static func anyChangeInTheTextChangesTheID(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.changedText) { input in
            let (a, b) = input
            #expect(identity.id(entity, a, "r1") != (identity.id(entity, b, "r1")))
        }
    }

    /// The reader version is stored beside the line and never changes its id.
    static func theReaderVersionNeverChangesTheID(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.spacedPair) { input in
            let (text, _) = input
            #expect(
                identity.id(entity, text, "whatsapp-reader 1") == identity.id(entity, text, "whatsapp-reader 2"))
        }
    }

    /// The identity text is NFC, and normalizing it again changes nothing.
    static func identityTextIsNFCAndStable(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.anyText) { input in
            let (text) = input
            let once = identity.normalize(text)
            #expect(identity.normalize(once) == once)
            #expect(Array(once.unicodeScalars) == Array(once.precomposedStringWithCanonicalMapping.unicodeScalars))
        }
    }

    /// In one read, every element is its own line, also two equal texts; reading the same screen again gives the
    /// same ids in the same order.
    static func duplicatesInOneReadStayDistinctAndStable(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.screenRead) { input in
            let (read, _, _) = input
            let ids = identity.screen("app place", read)
            #expect(Set(ids).count == read.count)
            #expect(identity.screen("app place", read) == ids)
        }
    }

    /// A read in another order, or a scrolled part of it, maps onto lines of the full read: no ghost line.
    static func reorderedOrScrolledReadsMapOntoTheSameLines(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.screenRead) { input in
            let (read, shuffled, window) = input
            let ids = Set(identity.screen("app place", read))
            #expect(Set(identity.screen("app place", shuffled)) == ids)
            #expect(Set(identity.screen("app place", window)).isSubset(of: ids))
        }
    }

    /// The instant makes the id, never the wall time of the zone the reader resolved it in.
    static func theInstantNotTheLocalTimeMakesTheID(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.instantInTwoZones) { input in
            let (millis, zoneA, zoneB) = input
            let instant = Date(timeIntervalSince1970: Double(millis) / 1000)
            /// The instant as a reader in `zoneName` writes it (local time with its offset) and reads it back.
            func resolved(in zoneName: String) -> (Date, TimeZone) {
                let zone = TimeZone(identifier: zoneName)!
                let format = ISO8601DateFormatter()
                format.timeZone = zone
                return (format.date(from: format.string(from: instant))!, zone)
            }
            let (dateA, a) = resolved(in: zoneA)
            let (dateB, b) = resolved(in: zoneB)
            #expect(identity.calendar(dateA, a) == (identity.calendar(dateB, b)))
        }
    }

    /// A view is its lines in reading order: the same lines in another order are another view.
    static func aViewIsItsLinesInOrder(_ identity: LineIdentity) async {
        await propertyCheck(count: cases, input: LineWorld.reorderedView) { input in
            let (lines, other) = input
            #expect(identity.view("app place", lines) == identity.view("app place", lines))
            #expect(identity.view("app place", lines) != identity.view("app place", other))
        }
    }
}
