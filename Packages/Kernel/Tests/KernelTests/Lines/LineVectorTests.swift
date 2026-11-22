import Kernel
import Testing

@testable import Lines

/// Fixed vectors. Each expected value comes from `worktrace/bin/lines-vectors/derive.py`, which shares no code with
/// `Lines` (Python hashlib, unicodedata, struct). A change to framing, tags, field order or normalization changes them.
@Suite struct LineVectorTests {
    static let direct = (chat: "919812345678@s.whatsapp.net", stanza: "3EB0C4F2A1B2C3D4E5F6")
    static let group = (chat: "120363041234567890@g.us", stanza: "ABCDEF0123456789")
    static let page = "com.apple.Safari https://example.com/notes"
    static let messy = " Cafe\u{301}\u{A0}\u{A0}\u{91C}\u{93C}\u{930}\u{942}\u{930}\u{940}\u{200B}\u{200E}\n"

    static func vectors() throws -> [String] {
        let direct = try EntityKey.whatsAppDirect(chat: direct.chat, fromMe: false, stanzaID: direct.stanza)
        let repeated = try EntityKey.whatsAppDirect(
            chat: Self.direct.chat, fromMe: false, stanzaID: Self.direct.stanza, occurrence: 1)
        let fromMember = try EntityKey.whatsAppGroup(
            chat: group.chat, author: .member("919876543210@s.whatsapp.net"), stanzaID: group.stanza)
        let fromMe = try EntityKey.whatsAppGroup(chat: group.chat, author: .me, stanzaID: group.stanza)
        let gmail = try EntityKey.gmail(messageID: "18c2f3a4b5d6e7f8")
        let calendar = try EntityKey.calendar(
            externalID: "7kq3m0v9@google.com", occurrence: UTCInstant(milliseconds: 1_795_305_600_000))
        let screen = try Line.screen(container: page, texts: ["ok", "ok"], readerVersion: "ax 1")
        let lines = [
            Line(entity: direct, text: "Kal deck bhejo, 5 baje tak.", readerVersion: "wa 1"),
            Line(entity: fromMember, text: "हिन्दी में भेजो", readerVersion: "wa 1"),
            Line(entity: gmail, text: "Please find the deck attached.", readerVersion: "gmail 1"),
            Line(entity: calendar, text: "Investor call", readerVersion: "ek 1"),
            screen[0], screen[1],
            Line(entity: direct, text: messy, readerVersion: "wa 1"),
            Line(entity: direct, text: "\u{915}\u{94D}\u{200D}\u{937}", readerVersion: "wa 1"),
            Line.tombstone(entity: gmail, readerVersion: "gmail 1"),
            Line(entity: repeated, text: "Kal deck bhejo, 5 baje tak.", readerVersion: "wa 1"),
            Line(entity: fromMe, text: "ok", readerVersion: "wa 1"),
        ]
        let view = ViewID(container: page, lines: [screen[0].id, screen[1].id])
        let audience = AudienceDigest(
            owner: "919812345678@s.whatsapp.net",
            members: [WhatsAppJID.canonical("919876543210@c.us"), "1234@lid", "919812345678@s.whatsapp.net"])
        return lines.map(\.id.description) + [view.description, audience.description]
    }

    static let pinned = [
        "f8455e5be0684fc5ac9607ba43e59de5b00e8e1b9c421c2995ca6746869071a3",
        "4dd322e5226fb94256e3820421a508216ddd4c619b104bfa70fe63791820655c",
        "4c9db6b38ce2c451a7eb806e4e951aca1613b7610ce513d9457242540826206a",
        "f8a999074d024efc408196700015168906e9ddfdd8c677631757e8bebec9228a",
        "304e817441984c64d34243d287ea67be7c73413cc1b3a82a35a4a492503c18fa",
        "f2a0a3e91889092f14cdd422e662a55a7d902081254d5b9c4420345119dcea2d",
        "a87ef405b872d8d2849dcd2b52683ea6f03fc9147d71f21eac2524956f49b0f8",
        "425b967b29eb20a4f1eef4161d14dcbcac7c6b0532fa9d7f381d1bd107ff1495",
        "12ec9f10f653a03a3a19cc2d1efc379681ccc508c389bcdab4dc0329cd1b5121",
        "ccf493a49be0e32caec764a4de7eb65c46cdb8d437d56ff41d7a27b3b878cc23",
        "ee56122b455bfa893be637c948d04eedad212696a3fc10e67f32d5a3da9e7f7a",
        "99759a56863f95928900a8e0b31921a0020866c5453dd5fd35151ae8bceed923",
        "e308af1d9fe0df8b104526d7b2211659534ac217cab944d0c830775d62d50a0e",
    ]

    @Test func everyVectorMatchesTheIndependentDerivation() throws {
        #expect(try Self.vectors() == Self.pinned)
    }

    /// The layout of an entity key: the tag, the kind, then each field with a 4-byte big-endian length; the author is
    /// one byte and an empty jid part for me or the other person; the occurrence is a big-endian UInt32.
    @Test func theEntityKeyBytesArePinned() throws {
        let key = try EntityKey.whatsAppDirect(chat: Self.direct.chat, fromMe: false, stanzaID: Self.direct.stanza)
        let hex = key.bytes.map { String($0 >> 4, radix: 16) + String($0 & 0xF, radix: 16) }.joined()
        #expect(
            hex == "00000013776f726b62656e63682e656e746974792e76310000000877686174736170700000001b393139383132333435"
                + "36373840732e77686174736170702e6e65740000000101000000000000001433454230433446324131423243334434453546"
                + "360000000400000000")
    }

    /// The two copies of "ok" in one screen read are two lines; the identity text of the messy vector is clean.
    @Test func theVectorInputsMeanWhatTheyClaim() throws {
        #expect(Set(try Self.vectors()).count == Self.pinned.count)
        #expect(IdentityText.normalize(Self.messy) == "Caf\u{E9} \u{91C}\u{93C}\u{930}\u{942}\u{930}\u{940}")
        #expect(IdentityText.normalize("\u{915}\u{94D}\u{200D}\u{937}") == "\u{915}\u{94D}\u{200D}\u{937}")
    }
}

/// The white space table equals the platform's Unicode White_Space property for every scalar, so a Unicode update
/// that changes the property turns this red.
@Suite struct IdentityTextTableTests {
    @Test func theWhiteSpaceTableIsTheUnicodeProperty() {
        let scalars = (0...0x10FFFF).compactMap(Unicode.Scalar.init(_:)) as [Unicode.Scalar]
        let differing = scalars.filter { IdentityText.isWhiteSpace($0.value) != $0.properties.isWhitespace }
        #expect(differing.isEmpty)
    }

    /// Every character the identity drops is a format character (Cf), and none of them is ZWJ or ZWNJ.
    @Test func everyDroppedCharacterIsAFormatCharacterButTheJoiners() {
        let dropped = (0...0x10FFFF).compactMap(Unicode.Scalar.init(_:)).filter { IdentityText.isInvisible($0.value) }
        #expect(dropped.allSatisfy { $0.properties.generalCategory == .format })
        #expect(dropped.count == 16)
        #expect(!dropped.contains("\u{200C}") && !dropped.contains("\u{200D}"))
    }
}
