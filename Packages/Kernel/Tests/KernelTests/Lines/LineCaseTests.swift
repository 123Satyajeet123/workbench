import Foundation
import Lines
import Testing

/// Fixed cases for rules the laws do not reach (each one found by a mutation that survived the laws).
@Suite struct LineCaseTests {
    @Test func anEmptyFieldIsRefused() {
        #expect(throws: EntityKeyError.emptyField("chat")) {
            try EntityKey.whatsAppDirect(chat: "", fromMe: false, stanzaID: "s")
        }
        #expect(throws: EntityKeyError.emptyField("stanzaID")) {
            try EntityKey.whatsAppDirect(chat: "c", fromMe: false, stanzaID: "")
        }
        #expect(throws: EntityKeyError.emptyField("member")) {
            try EntityKey.whatsAppGroup(chat: "1@g.us", author: .member(""), stanzaID: "s")
        }
        #expect(throws: EntityKeyError.emptyField("messageID")) { try EntityKey.gmail(messageID: "") }
        #expect(throws: EntityKeyError.emptyField("externalID")) {
            try EntityKey.calendar(externalID: "", occurrence: UTCInstant(milliseconds: 0))
        }
        #expect(throws: EntityKeyError.emptyField("container")) {
            try EntityKey.screen(container: "", content: ContentHash(text: "ok"), ordinal: 0)
        }
    }

    @Test func entityFieldsAreComparedInNFC() throws {
        let composed = try EntityKey.gmail(messageID: "Caf\u{E9}")
        let decomposed = try EntityKey.gmail(messageID: "Cafe\u{301}")
        #expect(composed == decomposed)
    }

    @Test func theStoredTextIsNFCWithItsLineBreaks() throws {
        let line = Line(entity: try .gmail(messageID: "m"), text: "Cafe\u{301}\nnext", readerVersion: "r1")
        #expect(Array(line.text.unicodeScalars) == Array("Caf\u{E9}\nnext".unicodeScalars))
    }

    @Test func aScreenTextWithNothingVisibleIsNoLine() throws {
        let lines = try Line.screen(container: "c", texts: ["ok", " \n", "\u{200B}", "ok"], readerVersion: "r1")
        #expect(lines.map(\.text) == ["ok", "ok"])
    }

    @Test func aDateBecomesTheNearestMillisecond() {
        #expect(UTCInstant(Date(timeIntervalSince1970: 1.0006)).milliseconds == 1001)
        #expect(UTCInstant(Date(timeIntervalSince1970: 1.0004)).milliseconds == 1000)
    }

    /// The web client's `@c.us` and the store's `@s.whatsapp.net` name one account; `@lid` is another name.
    @Test func everyReaderGivesOneMessageOneKey() throws {
        let store = try EntityKey.whatsAppDirect(chat: "91@s.whatsapp.net", fromMe: false, stanzaID: "3EB0")
        let web = try EntityKey.whatsAppDirect(chat: "91@c.us", fromMe: false, stanzaID: "3EB0")
        let lid = try EntityKey.whatsAppDirect(chat: "91@lid", fromMe: false, stanzaID: "3EB0")
        #expect(store == web && store != lid)
        let member = try EntityKey.whatsAppGroup(chat: "1@g.us", author: .member("91@s.whatsapp.net"), stanzaID: "s")
        #expect(try member == EntityKey.whatsAppGroup(chat: "1@g.us", author: .member("91@c.us"), stanzaID: "s"))
        #expect(WhatsAppJID.canonical("91@c.us.example") == "91@c.us.example")
    }

    @Test func aChatOfTheWrongKindIsRefused() {
        #expect(throws: EntityKeyError.wrongChatKind("1@g.us")) {
            try EntityKey.whatsAppDirect(chat: "1@g.us", fromMe: false, stanzaID: "s")
        }
        #expect(throws: EntityKeyError.wrongChatKind("91@s.whatsapp.net")) {
            try EntityKey.whatsAppGroup(chat: "91@c.us", author: .me, stanzaID: "s")
        }
    }

    /// Me, the other person, and a member are three authors; a repeated stanza id gets its own key.
    @Test func authorAndOccurrenceArePartOfTheKey() throws {
        let keys = try [
            EntityKey.whatsAppDirect(chat: "91@s.whatsapp.net", fromMe: true, stanzaID: "s"),
            EntityKey.whatsAppDirect(chat: "91@s.whatsapp.net", fromMe: false, stanzaID: "s"),
            EntityKey.whatsAppDirect(chat: "91@s.whatsapp.net", fromMe: false, stanzaID: "s", occurrence: 1),
            EntityKey.whatsAppGroup(chat: "1@g.us", author: .me, stanzaID: "s"),
            EntityKey.whatsAppGroup(chat: "1@g.us", author: .member("91@s.whatsapp.net"), stanzaID: "s"),
        ]
        #expect(Set(keys).count == keys.count)
    }

    /// A message with only invisible characters and the tombstone of that message are two lines.
    @Test func aTombstoneIsNeverATextLine() throws {
        let key = try EntityKey.gmail(messageID: "m")
        let invisible = Line(entity: key, text: "\u{200B}", readerVersion: "r1")
        let tombstone = Line.tombstone(entity: key, readerVersion: "r1")
        #expect(invisible.id != tombstone.id && tombstone.isTombstone && !invisible.isTombstone)
        #expect(tombstone.text.isEmpty && !Line(entity: key, text: "", readerVersion: "r1").isTombstone)
    }

    /// Direction marks leave the id alone and stay in the stored text.
    @Test func directionMarksChangeNoIDAndStayInTheText() throws {
        let key = try EntityKey.gmail(messageID: "m")
        let marked = Line(entity: key, text: "\u{200F}ok\u{2066}", readerVersion: "r1")
        #expect(marked.id == Line(entity: key, text: "ok", readerVersion: "r1").id)
        #expect(marked.text.unicodeScalars.count == 4)
    }

    /// Two readings of one line by two reader versions are one line.
    @Test func lineEqualityIsItsID() throws {
        let key = try EntityKey.gmail(messageID: "m")
        let first = Line(entity: key, text: "ok  done", readerVersion: "r1")
        let second = Line(entity: key, text: "ok done", readerVersion: "r2")
        #expect(first == second && Set([first, second]).count == 1)
        #expect(first != Line(entity: key, text: "ok", readerVersion: "r1"))
    }

    /// Order and repeats of members do not matter; the owner is a member; any other member changes the digest.
    @Test func theAudienceDigestIsTheMemberSet() {
        let digest = AudienceDigest(owner: "me", members: ["a", "b"])
        #expect(digest == AudienceDigest(owner: "me", members: ["b", "a", "a", "me"]))
        #expect(digest == AudienceDigest(owner: "a", members: ["me", "b"]))
        #expect(digest != AudienceDigest(owner: "me", members: ["a"]))
        #expect(digest != AudienceDigest(owner: "me", members: ["a", "b", "c"]))
        #expect(AudienceDigest(owner: "Caf\u{E9}", members: []) == AudienceDigest(owner: "Cafe\u{301}", members: []))
    }
}
