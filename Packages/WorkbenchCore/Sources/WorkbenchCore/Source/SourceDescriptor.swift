import Foundation
import Kernel
import Lines

/// What one source of evidence is, as data (research 56 §1 Sources row): the consent kind it needs, how the model
/// reads its lines, how long its lines live, how it gives its text, and how far back it looks for edits. A reader
/// (`EvidenceSource`) carries one. Every field here is read by code; a new source adds the fields it needs (label
/// kind, audience proof, cost class, a second cursor kind) in the change that reads them.
public struct SourceDescriptor: Sendable, Equatable {
    /// How long lines live. The raw value is the `retention_class` of the line.
    public enum Retention: String, Sendable { case chat, mail, page, file, note, screen, call }

    /// How the source gives its text. The raw value is the `obtained_by` of the line.
    public enum Obtained: String, Sendable {
        case db
        /// A service the source asks for each message, such as Telegram.
        case api
        case domText = "dom_text"
        case axValue = "ax_value"
        /// Speech recognized on this Mac.
        case speech
    }

    /// The source's own name, unique across sources: the key of its `SourceID`.
    public let key: String
    /// Older names that mean this source: the raw values of `HelperSpec.Source`.
    public let aliases: [String]
    public let consent: SourceKind
    /// What the model is told about the lines it reads from this source.
    public let grammar: String
    public let retention: Retention
    public let obtainedBy: Obtained
    /// How far before its last read a reader looks again for edited messages.
    public let editWindow: TimeInterval
    /// How many lines on each side of a line a fact cites belong to its evidence. Nil: the whole container, because
    /// the container is one subject, such as a mail thread.
    public var evidenceReach: Int?
    /// A group is read only while its audience is the one the person confirmed as all agreed. `Store.agree` records
    /// that audience, and a write whose audience differs is refused inside the write transaction.
    public var requiresAgreedAudience = false

    /// The id of this source for one owner. Two owners never share one.
    public func sourceID(owner: PersonID) throws(IdentifierError) -> SourceID {
        Kernel.Source(owner: owner, key: try SourceKey(key)).id
    }
}

extension SourceDescriptor {
    private static let whatsAppGrammar = """
        one work day of a WhatsApp group. Each line is `[number] HH:mm sender: text`. People write in Hindi, \
        English and Hinglish.
        """

    public static let whatsAppChat = SourceDescriptor(
        key: "whatsapp.chat", aliases: ["whatsapp_chat"], consent: .whatsapp, grammar: whatsAppGrammar,
        retention: .chat, obtainedBy: .db, editWindow: Scan.chatEditWindow, evidenceReach: 20)
}

extension SourceDescriptor {
    private static let telegramGrammar = """
        one work day of a Telegram group. Each line is `[number] HH:mm sender: text`. People write in Hindi, \
        English and Hinglish.
        """

    /// One Telegram group, read through the founder's own account. Telegram lets an app pass chat data to a model only
    /// when every person in the chat agrees, so a group is read only for the audience the founder confirmed.
    public static let telegramChat = SourceDescriptor(
        key: "telegram.chat", aliases: ["telegram_chat"], consent: .telegram, grammar: telegramGrammar,
        retention: .chat, obtainedBy: .api, editWindow: 0, evidenceReach: 20, requiresAgreedAudience: true)
}

extension SourceDescriptor {
    private static let gmailGrammar = """
        the mail threads the investor opened in the label they named, in order. Each line is `[number] sender: the \
        text`. A line of an attached deck also names the file and the page: `sender — file page 3: the text`. A \
        thread shows one line for each message and each deck page.
        """

    /// Gmail read by the browser extension, one label at a time. The grant label is the Gmail label the person named.
    public static let gmailMail = SourceDescriptor(
        key: "mail.gmail", aliases: ["mail_threads"], consent: .mail, grammar: gmailGrammar, retention: .mail,
        obtainedBy: .domText, editWindow: 0)
}

extension SourceDescriptor {
    private static let pageGrammar = """
        the text of web pages the founder had on screen, in order. Each line is `[number] HH:mm site — page \
        title: the text on screen`. The same page can appear again after a scroll, with new text.
        """

    /// The text of web pages, read by the browser extension. The grant label is the site; the sites a machine reads are
    /// that machine's own choice among the sites the person allowed.
    public static let webPage = SourceDescriptor(
        key: "web.page", aliases: ["page_text"], consent: .screenText, grammar: pageGrammar, retention: .page,
        obtainedBy: .domText, editWindow: 0)
}

extension SourceDescriptor {
    /// The words the person typed by hand: a claim on a deal, or a fact they added. The person's act is the consent.
    public static let typedNote = SourceDescriptor(
        key: "note.typed", aliases: [], consent: .typed,
        grammar: """
            what the person typed by hand: a claim on a deal, or a fact they added. Each line is `[number] who: the \
            words`.
            """, retention: .file, obtainedBy: .db, editWindow: 0)

    /// A file the person added to a deal: the text of its pages. The person's act is the consent.
    public static let droppedFile = SourceDescriptor(
        key: "file.dropped", aliases: [], consent: .dropped,
        grammar: "a file the person added to a deal. Each line is `[number] who — file page N: the text`.",
        retention: .file, obtainedBy: .db, editWindow: 0)

    private static let screenWindowGrammar = """
        the windows the founder had in front, in order. Each line is `[number] HH:mm–HH:mm (minutes) app — window \
        title — address`; the address is a web page or a file and can be missing.
        """

    /// One stretch on one window, kept when it closes. The grant label is the app's bundle id.
    public static let screenWindow = SourceDescriptor(
        key: "screen.window", aliases: ["screen_sessions"], consent: .screen, grammar: screenWindowGrammar,
        retention: .screen, obtainedBy: .axValue, editWindow: 0)

    private static let screenTextGrammar = """
        the text one window showed, one line for each line on screen. Each line is `[number] HH:mm text`.
        """

    /// The text a window showed at one walk. The grant label is the app's bundle id.
    public static let screenText = SourceDescriptor(
        key: "screen.text", aliases: [], consent: .screen, grammar: screenTextGrammar, retention: .screen,
        obtainedBy: .axValue, editWindow: 0)
}

/// The sources this build knows. A source starts only when a machine names it.
public enum SourceRegistry {
    public static let all: [SourceDescriptor] = [
        .whatsAppChat, .telegramChat, .gmailMail, .webPage, .typedNote, .droppedFile, .note, .screenWindow, .screenText,
        .callTranscript,
    ]

    /// The source with this key or alias, or nil when no ported source has it.
    public static func descriptor(named name: String) -> SourceDescriptor? {
        all.first { $0.key == name || $0.aliases.contains(name) }
    }

    /// The source that reads under this consent kind, or nil when none does.
    public static func descriptor(consent: SourceKind) -> SourceDescriptor? { all.first { $0.consent == consent } }

    /// The sources that these names ask for, each once, in the order first named. A name no ported source has asks for
    /// nothing.
    public static func demanded(by names: some Sequence<String>) -> [SourceDescriptor] {
        var seen: Set<String> = []
        return names.compactMap { descriptor(named: $0) }.filter { seen.insert($0.key).inserted }
    }
}
