import Foundation
import Lines

/// The owner of every WhatsApp chat is a member of its audience, and the `actor` of the owner's own lines.
public enum WhatsAppAudience {
    public static let owner = "me"
}

/// A message id from the page: its `data-id`, as `true_<chat>_<stanza id>`. `true` is a message the owner sent. A
/// group message carries its sender after the stanza id.
struct WebMessageID: Equatable {
    let fromMe: Bool
    /// The chat, as the store names it (`@c.us` written as `@s.whatsapp.net`).
    let chat: String
    let stanza: String
    /// The account that sent it, in the store's form; nil when the id names none.
    let sender: String?

    init?(_ id: String) {
        guard id.utf8.count <= 256,
            let match = id.wholeMatch(
                of:
                    #/(true|false)_([0-9]+(?:-[0-9]+)?@(?:c\.us|s\.whatsapp\.net|g\.us|lid))_([A-Za-z0-9-]+)(?:_([0-9]+(?::[0-9]+)?@(?:c\.us|s\.whatsapp\.net|lid)))?/#
            )
        else { return nil }
        fromMe = match.1 == "true"
        chat = WhatsAppJID.canonical(String(match.2))
        stanza = String(match.3)
        sender = match.4.map { WhatsAppJID.canonical(String($0)) }
    }

    /// Who wrote it, in a group; nil when another account wrote it and the id names none.
    var groupAuthor: GroupAuthor? { fromMe ? .me : sender.map(GroupAuthor.member) }
}

/// An account id as the page writes it in an attribute: digits, then `@c.us`, `@s.whatsapp.net` or `@lid`. A name, a
/// number as shown, or any text is not one.
enum WebAccountID {
    static func isValid(_ text: String) -> Bool {
        text.utf8.count <= 64
            && text.wholeMatch(of: #/[0-9]+(?:-[0-9]+)?(?::[0-9]+)?@(?:c\.us|s\.whatsapp\.net|lid)/#) != nil
    }
}

/// What the extension read of the group-info panel the person opened: the ids found in the rows, the number of rows,
/// and the count the panel states. The panel proves a member list only when every row gave an id and the rows are as
/// many as the panel says; a list with a gap, or a name where an id should be, proves nothing.
struct WebPanel: Decodable, Sendable, Equatable {
    var ids: [String]
    var rows: Int
    var stated: Int?

    func membership() -> Membership? {
        guard rows > 0, ids.count == rows, stated == rows, ids.allSatisfy(WebAccountID.isValid) else { return nil }
        let canonical = ids.map(WhatsAppJID.canonical)
        guard Set(canonical).count == rows else { return nil }
        return Membership(members: canonical, proof: .infoPanel)
    }
}

/// Where a message may come from: a browser the policy knows, on the WhatsApp Web address, with no login in it.
enum WhatsAppWebPage {
    static let host = "web.whatsapp.com"

    static func isWhatsAppWeb(browser: String, url: String) -> Bool {
        guard CapturePolicy.browserBundleIDs.contains(browser), let address = URLComponents(string: url) else {
            return false
        }
        return address.scheme == "https" && address.host == host && (address.port ?? 443) == 443
            && address.user == nil && address.password == nil
    }
}

/// The chat that is open in the page, as the chooser asks for it: an id, a title, and the member list when the
/// panel is open. It holds no message.
struct WhatsAppChatSeen: Decodable, Sendable, Equatable {
    static let maximumTitle = 200

    var browser: String
    var url: String
    var chat: String
    var title: String
    var members: WebPanel?
}

enum WebSnapshotError: Error, Equatable {
    case notWhatsAppWeb
    case noMessages
    case tooManyMessages
    case tooMuchText
    case unrecognizedMessageID
    case repeatedMessageID
    case severalChats
    case senderUnknown
    case emptyText
    case deletedMessageWithText
}

/// What the extension read of the open WhatsApp Web chat: the messages the page had loaded, newest last. A message
/// the page shows as deleted has `deleted` and no text. `sent` is the page's own stamp of the message, as
/// `3:45 PM, 11/22/2026`. The extension reads rendered text only, never what is typed.
struct WhatsAppWebSnapshot: Decodable, Sendable, Equatable {
    static let host = WhatsAppWebPage.host
    static let maximumMessages = 200
    static let maximumCharacters = 20_000

    struct Message: Decodable, Sendable, Equatable {
        var id: String
        var text: String?
        var deleted: Bool?
        var sent: String?
    }

    /// One message of a snapshot that passed every check.
    struct Checked: Equatable {
        var id: WebMessageID
        /// Nil for a message deleted for everyone.
        var text: String?
        var sent: String?
    }

    var browser: String
    var url: String
    var messages: [Message]
    /// The member list the panel proves, when the person had it open.
    var members: WebPanel?

    /// The chat and its messages, or why the snapshot is refused whole. Every message id must name the same chat.
    func checked() throws(WebSnapshotError) -> (chat: String, messages: [Checked]) {
        guard WhatsAppWebPage.isWhatsAppWeb(browser: browser, url: url) else { throw .notWhatsAppWeb }
        guard !messages.isEmpty else { throw .noMessages }
        guard messages.count <= Self.maximumMessages else { throw .tooManyMessages }
        var checked: [Checked] = []
        var characters = 0
        for message in messages {
            guard let id = WebMessageID(message.id) else { throw .unrecognizedMessageID }
            let deleted = message.deleted == true
            let text = message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if deleted {
                guard text.isEmpty else { throw .deletedMessageWithText }
            } else {
                guard !text.isEmpty else { throw .emptyText }
            }
            if WhatsAppJID.isGroup(id.chat), id.groupAuthor == nil { throw .senderUnknown }
            characters += text.utf16.count
            guard characters <= Self.maximumCharacters else { throw .tooMuchText }
            checked.append(Checked(id: id, text: deleted ? nil : text, sent: message.sent))
        }
        guard Set(checked.map(\.id.chat)).count == 1 else { throw .severalChats }
        guard Set(checked.map { "\($0.id.fromMe)\($0.id.stanza)" }).count == checked.count else {
            throw .repeatedMessageID
        }
        return (checked[0].id.chat, checked)
    }
}
