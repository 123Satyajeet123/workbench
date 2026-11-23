import Foundation
import Kernel
import Lines

/// What one source of evidence is, as data (research 56 §1 Sources row): the consent kind it needs, how the model
/// reads its lines, how long its lines live, how it gives its text, and how far back it looks for edits. A reader
/// (`EvidenceSource`) carries one. Every field here is read by code; a new source adds the fields it needs (label
/// kind, audience proof, cost class, a second cursor kind) in the change that reads them.
public struct SourceDescriptor: Sendable, Equatable {
    /// How long lines live. The raw value is the `retention_class` of the line.
    public enum Retention: String, Sendable { case chat, mail, page }

    /// How the source gives its text. The raw value is the `obtained_by` of the line.
    public enum Obtained: String, Sendable {
        case db
        case domText = "dom_text"
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
        retention: .chat, obtainedBy: .db, editWindow: Scan.chatEditWindow)
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

/// The sources this build knows. A source starts only when a machine names it.
public enum SourceRegistry {
    public static let all: [SourceDescriptor] = [.whatsAppChat, .gmailMail, .webPage]

    /// The source with this key or alias, or nil when no ported source has it.
    public static func descriptor(named name: String) -> SourceDescriptor? {
        all.first { $0.key == name || $0.aliases.contains(name) }
    }

    /// The sources that these names ask for, each once, in the order first named. A name no ported source has asks for
    /// nothing.
    public static func demanded(by names: some Sequence<String>) -> [SourceDescriptor] {
        var seen: Set<String> = []
        return names.compactMap { descriptor(named: $0) }.filter { seen.insert($0.key).inserted }
    }
}
