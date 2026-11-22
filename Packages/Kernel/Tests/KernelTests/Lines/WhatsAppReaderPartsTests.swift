import Foundation
import Lines
import Testing

/// The pure parts of the WhatsApp store reader: type mapping, reply decoding, cursor arithmetic. Each check runs on
/// the code, and where a wrong version is easy to write, on that wrong version inside `withKnownIssue`.
@Suite struct WhatsAppReaderPartsTests {
    // MARK: Types

    /// The 31 type codes measured on the founder's store (research E-R3 §2), with whether any row of the type
    /// carries text.
    static let measuredTypes: [(code: Int, hasText: Bool)] = [
        (0, true), (6, true), (1, false), (7, true), (15, false), (59, false), (10, true), (2, false), (14, true),
        (8, true), (12, true), (19, false), (76, false), (42, true), (66, false), (11, false), (3, false),
        (75, false), (4, false), (20, false), (41, true), (55, false), (60, false), (43, true), (68, false),
        (25, true), (5, false), (28, false), (46, false), (13, false), (71, true),
    ]

    static func everyMeasuredTypeMapsAsDecided(_ treatment: (Int, Bool) -> WhatsAppMessageType.Treatment) {
        #expect(Set(measuredTypes.map(\.code)).count == 31)
        for (code, hasText) in measuredTypes {
            let expected: WhatsAppMessageType.Treatment =
                switch code {
                case 6, 10: .skipped
                case 14: .tombstone
                default: hasText ? .line : .skipped
                }
            #expect(treatment(code, hasText) == expected, "type \(code)")
        }
    }

    @Test func everyMeasuredTypeMapsAsDecided() {
        Self.everyMeasuredTypeMapsAsDecided { WhatsAppMessageType(code: $0).treatment(hasText: $1) }
    }

    @Test func aSystemTypeIsDroppedEvenWithTextAndOnlyRevokeIsATombstone() {
        withKnownIssue("planted break: the old filter, types 0, 1, 3, 8 only") {
            Self.everyMeasuredTypeMapsAsDecided { code, hasText in
                [0, 1, 3, 8].contains(code) && hasText ? .line : .skipped
            }
        }
        withKnownIssue("planted break: a revoke with text is a line") {
            Self.everyMeasuredTypeMapsAsDecided { code, hasText in
                code == 6 || code == 10 ? .skipped : (hasText ? .line : (code == 14 ? .tombstone : .skipped))
            }
        }
    }

    @Test func linksAreNamedAndUnnamedTypesKeepTheirCode() {
        #expect(WhatsAppMessageType(code: 7) == .link)
        #expect(WhatsAppMessageType(code: 42) == .other(42))
        #expect(WhatsAppMessageType(code: 14) == .revoked)
        #expect(WhatsAppMessageType(code: 6) == .systemNotice && WhatsAppMessageType(code: 10) == .systemNotice)
    }

    @Test func aMessageHasTheWordsOfItsTitleAndItsText() {
        #expect(WhatsAppMessageText.compose(title: "deck.pdf", text: "see this") == "deck.pdf — see this")
        #expect(WhatsAppMessageText.compose(title: nil, text: "hi") == "hi")
        #expect(WhatsAppMessageText.compose(title: "photo", text: nil) == "photo")
        #expect(WhatsAppMessageText.compose(title: "", text: "\u{200B} ") == "")
        #expect(WhatsAppMessageText.compose(title: nil, text: nil) == "")
    }

    // MARK: Replies

    static func field(_ number: UInt64, _ bytes: [UInt8]) -> [UInt8] {
        [UInt8(number << 3 | 2), UInt8(bytes.count)] + bytes
    }

    static func quoted(in blob: [UInt8], field number: UInt64 = WhatsAppReply.quotedStanzaField) -> String? {
        Protobuf.firstText(field: number, in: blob)
    }

    @Test func theQuotedStanzaIDIsFieldFive() {
        let stanza = Array("3EB0C767D0A1B2C3D4E5".utf8)
        let blob = Self.field(5, stanza) + Self.field(6, Array("919800000002@s.whatsapp.net".utf8))
        #expect(WhatsAppReply.quotedStanzaID(metadata: blob) == "3EB0C767D0A1B2C3D4E5")
        #expect(blob.first == 0x2A, "field 5, length-delimited: the first byte the census saw on 3,227 rows")
        withKnownIssue("planted break: the author field is read as the stanza id") {
            #expect(Self.quoted(in: blob, field: 6) == "3EB0C767D0A1B2C3D4E5")
        }
    }

    @Test func fieldsOfEveryWireTypeAreSkippedToReachFieldFive() {
        let blob: [UInt8] =
            [0x08, 0xAC, 0x02]  // field 1, varint 300
            + [0x11] + Array(repeating: 0, count: 8)  // field 2, 64-bit
            + [0x1D, 1, 2, 3, 4]  // field 3, 32-bit
            + Self.field(4, [9, 9, 9]) + Self.field(5, Array("abc".utf8))
        #expect(WhatsAppReply.quotedStanzaID(metadata: blob) == "abc")
        #expect(
            WhatsAppReply.quotedStanzaID(metadata: [0xA2, 0x01, 0x02, 7, 7] + Self.field(5, Array("x".utf8))) == "x",
            "the field is found wherever it sits, not only at the first byte")
    }

    @Test func aBlobWithoutAUsableFieldFiveGivesNoReply() {
        let stanza = Self.field(5, Array("abc".utf8))
        #expect(WhatsAppReply.quotedStanzaID(metadata: []) == nil)
        #expect(WhatsAppReply.quotedStanzaID(metadata: Self.field(6, Array("abc".utf8))) == nil, "no field 5")
        #expect(WhatsAppReply.quotedStanzaID(metadata: Self.field(5, [])) == nil, "an empty id")
        #expect(WhatsAppReply.quotedStanzaID(metadata: Self.field(5, [0xFF, 0xFE])) == nil, "not UTF-8")
        #expect(WhatsAppReply.quotedStanzaID(metadata: Array(stanza.dropLast())) == nil, "cut short")
        #expect(WhatsAppReply.quotedStanzaID(metadata: [0x2A, 0x7F, 0x61]) == nil, "length past the end")
        #expect(WhatsAppReply.quotedStanzaID(metadata: [0x0B] + stanza) == nil, "a group tag is not parsed")
        #expect(WhatsAppReply.quotedStanzaID(metadata: [0x08, 0x80] + stanza) == nil, "an unfinished varint")
        #expect(WhatsAppReply.quotedStanzaID(metadata: [UInt8](repeating: 0xFF, count: 12)) == nil)
    }

    @Test func aMalformedTailVoidsTheWholeBlob() {
        let blob = Self.field(5, Array("abc".utf8)) + [0x11, 1, 2]  // a 64-bit field cut short
        #expect(WhatsAppReply.quotedStanzaID(metadata: blob) == nil)
    }

    // MARK: Cursor

    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let window: TimeInterval = 3 * 86_400

    static func cursor(_ store: String = "U1", row: Int64 = 500, readAt: Date = now.addingTimeInterval(-86_400))
        -> ScanCursor
    {
        ScanCursor(storeID: store, lastRow: row, readAt: readAt)
    }

    static func scanPlan(_ state: ScanState, store: String = "U1") -> ScanPlan {
        Scan.plan(state: state, storeID: store, now: now, window: window)
    }

    @Test func theFirstReadStartsAtZeroAndMapsOldRowNumbers() {
        let plan = Self.scanPlan(ScanState())
        #expect(plan.after == 0 && plan.mapsLegacyRefs)
        #expect(plan.rescanSince == Self.now.addingTimeInterval(-Self.window))
    }

    @Test func aLaterReadStartsAtTheCursorAndTheWindowStartsAtTheLastRead() {
        let readAt = Self.now.addingTimeInterval(-7 * 86_400)
        let plan = Self.scanPlan(ScanState(cursor: Self.cursor(readAt: readAt), legacyMapped: true))
        #expect(plan.after == 500 && !plan.mapsLegacyRefs)
        #expect(plan.rescanSince == readAt.addingTimeInterval(-Self.window), "a Mac closed for a week still sees edits")
    }

    static func aChangedStoreVoidsTheCursor(_ plan: (ScanState, String) -> ScanPlan) {
        let state = ScanState(cursor: cursor(), legacyMapped: true)
        #expect(plan(state, "U1").after == 500)
        #expect(plan(state, "U2").after == 0, "a new store id: read it all again")
        #expect(!plan(state, "U2").mapsLegacyRefs, "the new numbers are not the numbers old citations used")
    }

    @Test func aChangedStoreVoidsTheCursor() {
        Self.aChangedStoreVoidsTheCursor { Self.scanPlan($0, store: $1) }
        withKnownIssue("planted break: the store id is not compared") {
            Self.aChangedStoreVoidsTheCursor { state, _ in Self.scanPlan(state, store: state.cursor?.storeID ?? "") }
        }
    }

    /// An erase deletes the cursor but not the fact that the old numbers were mapped: a new consent after a store
    /// change must not map the new store's numbers as old citations.
    @Test func oldNumbersAreMappedOnceEvenWhenTheCursorIsGone() {
        #expect(!Self.scanPlan(ScanState(cursor: nil, legacyMapped: true)).mapsLegacyRefs)
        #expect(Self.scanPlan(ScanState(cursor: Self.cursor(), legacyMapped: false)).mapsLegacyRefs)
    }

    @Test func theCursorMovesToTheHighestRowAndNeverBack() {
        let plan = Self.scanPlan(ScanState(cursor: Self.cursor(), legacyMapped: true))
        let later = Self.now.addingTimeInterval(60)
        #expect(Scan.cursor(after: plan, storeID: "U1", highestRow: 620, readAt: later).lastRow == 620)
        #expect(Scan.cursor(after: plan, storeID: "U1", highestRow: 480, readAt: later).lastRow == 500)
        #expect(Scan.cursor(after: plan, storeID: "U1", highestRow: nil, readAt: later).lastRow == 500)
        let voided = Self.scanPlan(ScanState(cursor: Self.cursor(), legacyMapped: true), store: "U2")
        #expect(
            Scan.cursor(after: voided, storeID: "U2", highestRow: 40, readAt: later)
                == ScanCursor(storeID: "U2", lastRow: 40, readAt: later))
    }

    static func aStoredCursorOnlyMovesForward(_ keep: (ScanCursor, ScanCursor?) -> ScanCursor) {
        let stored = cursor(row: 600, readAt: now)
        let older = cursor(row: 500, readAt: now.addingTimeInterval(-60))
        #expect(keep(older, stored).lastRow == 600 && keep(older, stored).readAt == now, "a late write does not undo")
        #expect(keep(cursor(row: 700, readAt: now.addingTimeInterval(60)), stored).lastRow == 700)
        #expect(keep(older, nil) == older)
        #expect(keep(cursor("U2", row: 5), stored).storeID == "U2", "another store replaces it")
    }

    @Test func aStoredCursorOnlyMovesForward() {
        Self.aStoredCursorOnlyMovesForward { $0.advanced(from: $1) }
        withKnownIssue("planted break: the new cursor always wins") {
            Self.aStoredCursorOnlyMovesForward { new, _ in new }
        }
    }

    @Test func theCursorIsJSONAndRoundTrips() throws {
        let cursor = Self.cursor("5F2A", row: 29_114, readAt: Date(timeIntervalSince1970: 1_800_000_000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(ScanCursor.self, from: encoder.encode(cursor)) == cursor)
    }
}
