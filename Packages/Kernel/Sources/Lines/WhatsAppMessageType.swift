// Source: built (research E-R3 §2 and §8.1: 31 type codes measured on the founder's store; research 56 §1 WhatsApp
// reader row; founder decision 2026-11-22: a revoke erases the text).

/// What a `ZMESSAGETYPE` code of the WhatsApp Desktop store means to the reader. The named codes are the ones public
/// sources and our census agree on. Any other code is `other(code)`: its meaning is not guessed, and it is read only
/// when it carries text.
public enum WhatsAppMessageType: Hashable, Sendable {
    case text, image, video, voiceNote, contact, location, link, document, gif, sticker, call
    /// "Delete for everyone": the store rewrites the message in place.
    case revoked
    /// A group event or another notice that the app wrote. It is nobody's words.
    case systemNotice
    case other(Int)

    /// The code the store gives a message deleted for everyone. A read asks for every such row, whatever its age.
    public static let revokedCode = 14

    public init(code: Int) {
        self =
            switch code {
            case 0: .text
            case 1: .image
            case 2: .video
            case 3: .voiceNote
            case 4: .contact
            case 5: .location
            case 6, 10: .systemNotice
            case 7: .link
            case 8: .document
            case 11: .gif
            case Self.revokedCode: .revoked
            case 15: .sticker
            case 59: .call
            default: .other(code)
            }
    }

    /// What the reader writes for a message of this type.
    public enum Treatment: Hashable, Sendable {
        /// A line with the message's text.
        case line
        /// A line with no text: the message was deleted for everyone, and its earlier text is erased.
        case tombstone
        /// No line. The reader counts it.
        case skipped
    }

    /// `hasText` is whether the message has words a person can read (see `WhatsAppMessageText`).
    public func treatment(hasText: Bool) -> Treatment {
        switch self {
        case .revoked: .tombstone
        case .systemNotice: .skipped
        default: hasText ? .line : .skipped
        }
    }
}

/// The words of one message: the caption or file title of its media row, then its own text.
public enum WhatsAppMessageText {
    public static let separator = " — "

    /// The parts that show something, in order, joined. Empty when the message has no words.
    public static func compose(title: String?, text: String?) -> String {
        [title, text].compactMap { $0 }.filter { !IdentityText.normalize($0).isEmpty }.joined(separator: separator)
    }
}
