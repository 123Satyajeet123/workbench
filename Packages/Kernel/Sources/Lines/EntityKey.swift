// Source: built (research 56 §1 line identity row and §9; research E-R3 §4 stanza identity and the `#n` tie-break;
// research E-R4 §7 EventKit identity). Framing is Kernel's (ADR-003).

import Foundation
import Kernel

public enum EntityKeyError: Error, Equatable, Sendable {
    /// A field that names the entity is empty after NFC: the field's name.
    case emptyField(String)
    /// A group key was asked for a chat jid that is not a group (`@g.us`), or a direct key for one that is.
    case wrongChatKind(String)
}

/// WhatsApp account ids in one form for every reader.
public enum WhatsAppJID {
    /// NFC, with the web client's `@c.us` written as the store's `@s.whatsapp.net`. A `@lid` id stays as it is; a
    /// lid-to-phone map is data kept beside the lines, never part of a key.
    public static func canonical(_ jid: String) -> String {
        let text = jid.precomposedStringWithCanonicalMapping
        guard text.hasSuffix("@c.us") else { return text }
        return String(text.dropLast("@c.us".count)) + "@s.whatsapp.net"
    }

    /// Whether the jid names a group chat (`@g.us`).
    public static func isGroup(_ jid: String) -> Bool { jid.hasSuffix("@g.us") }
}

/// Who sent a message in a group chat.
public enum GroupAuthor: Hashable, Sendable {
    case me
    /// Another member, by jid.
    case member(String)
}

/// What a line is about, apart from its text: the source's own name for the thing it read. Two readings of one
/// message have one entity key; an edit keeps the key and changes the text. The key is canonical bytes: the domain
/// tag, the kind, then each field, every part with a 4-byte big-endian length. Text fields are NFC.
public struct EntityKey: Hashable, Sendable {
    static let domain = "workbench.entity.v1"

    public let bytes: [UInt8]

    private init(kind: String, _ fields: [[UInt8]]) {
        bytes = Framing.bytes(Self.domain, [Array(kind.utf8)] + fields)
    }

    /// A message in a one-to-one chat: the chat jid, whether I sent it, and its stanza id. `occurrence` is the
    /// message's place among rows with this chat, author and stanza id, in the source's order (the store reader:
    /// ascending `Z_PK`); it is 0 except for a repeated stanza id.
    public static func whatsAppDirect(chat: String, fromMe: Bool, stanzaID: String, occurrence: UInt32 = 0)
        throws(EntityKeyError) -> EntityKey
    {
        let chat = WhatsAppJID.canonical(chat)
        guard !WhatsAppJID.isGroup(chat) else { throw .wrongChatKind(chat) }
        return whatsApp(
            chat: try field(chat, "chat"), author: fromMe ? .me : .peer, stanzaID: try field(stanzaID, "stanzaID"),
            occurrence)
    }

    /// A message in a group chat (`@g.us`): the chat jid, its author, and its stanza id. A message from another member
    /// carries that member's jid. `occurrence` as for a direct message.
    public static func whatsAppGroup(chat: String, author: GroupAuthor, stanzaID: String, occurrence: UInt32 = 0)
        throws(EntityKeyError) -> EntityKey
    {
        let chat = WhatsAppJID.canonical(chat)
        guard WhatsAppJID.isGroup(chat) else { throw .wrongChatKind(chat) }
        let sender: Author
        switch author {
        case .me: sender = .me
        case .member(let jid): sender = .member(try field(WhatsAppJID.canonical(jid), "member"))
        }
        return whatsApp(
            chat: try field(chat, "chat"), author: sender, stanzaID: try field(stanzaID, "stanzaID"), occurrence)
    }

    private enum Author {
        case me, peer
        case member([UInt8])

        var parts: [[UInt8]] {
            switch self {
            case .me: [[0], []]
            case .peer: [[1], []]
            case .member(let jid): [[2], jid]
            }
        }
    }

    private static func whatsApp(chat: [UInt8], author: Author, stanzaID: [UInt8], _ occurrence: UInt32) -> EntityKey {
        EntityKey(kind: "whatsapp", [chat] + author.parts + [stanzaID, BigEndian.bytes(occurrence)])
    }

    /// A Gmail message, by its Gmail API message id.
    public static func gmail(messageID: String) throws(EntityKeyError) -> EntityKey {
        EntityKey(kind: "gmail", [try field(messageID, "messageID")])
    }

    /// An item a web site named itself (a Slack message by its timestamp, a Gmail message by its page id): the site, the
    /// place it is in (a channel, a thread) and its id there.
    public static func web(site: String, container: String, itemID: String) throws(EntityKeyError) -> EntityKey {
        EntityKey(
            kind: "web", [try field(site, "site"), try field(container, "container"), try field(itemID, "itemID")])
    }

    /// One occurrence of a calendar event: EventKit's `calendarItemExternalIdentifier` and the occurrence's start.
    public static func calendar(externalID: String, occurrence: UTCInstant) throws(EntityKeyError) -> EntityKey {
        EntityKey(kind: "calendar", [try field(externalID, "externalID"), occurrence.bytes])
    }

    /// A text on screen: the container it was read in, its content, and which copy it is among equal texts in that
    /// container (see `Line.screen`).
    public static func screen(container: String, content: ContentHash, ordinal: UInt32) throws(EntityKeyError)
        -> EntityKey
    {
        EntityKey(kind: "screen", [try field(container, "container"), content.bytes, BigEndian.bytes(ordinal)])
    }

    private static func field(_ text: String, _ name: String) throws(EntityKeyError) -> [UInt8] {
        let bytes = Array(text.precomposedStringWithCanonicalMapping.utf8)
        guard !bytes.isEmpty else { throw .emptyField(name) }
        return bytes
    }
}
