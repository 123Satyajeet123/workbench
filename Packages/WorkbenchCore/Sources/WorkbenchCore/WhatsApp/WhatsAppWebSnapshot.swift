import Foundation
import Lines

/// The owner of every WhatsApp chat is a member of its audience, and the `actor` of the owner's own lines.
public enum WhatsAppAudience {
    public static let owner = "me"
}

/// A message id from the page: its `data-id`, as `true_<chat>_<stanza id>`. `true` is a message the owner sent. A
/// group message carries a sender after the stanza id; it is accepted and not kept.
struct WebMessageID: Equatable {
    let fromMe: Bool
    /// The chat, as the store names it (`@c.us` written as `@s.whatsapp.net`).
    let chat: String
    let stanza: String

    init?(_ id: String) {
        guard id.utf8.count <= 256,
            let match = id.wholeMatch(
                of:
                    #/(true|false)_([0-9]+(?:-[0-9]+)?@(?:c\.us|s\.whatsapp\.net|g\.us|lid))_([A-Za-z0-9-]+)(?:_[0-9]+(?::[0-9]+)?@(?:c\.us|s\.whatsapp\.net|lid))?/#
            )
        else { return nil }
        fromMe = match.1 == "true"
        chat = WhatsAppJID.canonical(String(match.2))
        stanza = String(match.3)
    }
}

enum WebSnapshotError: Error, Equatable {
    case notWhatsAppWeb
    case noMessages
    case tooManyMessages
    case tooMuchText
    case unrecognizedMessageID
    case repeatedMessageID
    case severalChats
    case emptyText
    case deletedMessageWithText
}

/// What the extension read of the open WhatsApp Web chat: the messages the page had loaded, newest last. A message
/// the page shows as deleted has `deleted` and no text. `sent` is the page's own stamp of the message, as
/// `3:45 PM, 11/22/2026`. The extension reads rendered text only, never what is typed.
struct WhatsAppWebSnapshot: Decodable, Sendable, Equatable {
    static let host = "web.whatsapp.com"
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

    /// The chat and its messages, or why the snapshot is refused whole. Every message id must name the same chat.
    func checked() throws(WebSnapshotError) -> (chat: String, messages: [Checked]) {
        guard CapturePolicy.browserBundleIDs.contains(browser), isWhatsAppWebAddress else {
            throw .notWhatsAppWeb
        }
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

    private var isWhatsAppWebAddress: Bool {
        guard let address = URLComponents(string: url) else { return false }
        return address.scheme == "https" && address.host == Self.host && (address.port ?? 443) == 443
            && address.user == nil && address.password == nil
    }
}
