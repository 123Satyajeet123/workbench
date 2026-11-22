import Foundation
import Kernel
import Lines

/// What one source of evidence is, as data (research 56 §1 Sources row): the consent kind it needs, how the model
/// reads its lines, how long its lines live, how it gives its text, and how far back it looks for edits. A reader
/// (`EvidenceSource`) carries one. Every field here is read by code; a new source adds the fields it needs (label
/// kind, audience proof, cost class, a second cursor kind) in the change that reads them.
public struct SourceDescriptor: Sendable, Equatable {
    /// How long lines live. The raw value is the `retention_class` of the line.
    public enum Retention: String, Sendable { case chat }

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
    /// The key of the source this one stands in for: it writes a chat only while that source cannot read it. Two
    /// sources that write one chat would give two texts for one entity key, which looks like an edit.
    public let fallbackFor: String?

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
        retention: .chat, obtainedBy: .db, editWindow: Scan.chatEditWindow, fallbackFor: nil)

    /// The WhatsApp Web page, read by the browser extension. It reads one chat at a time and has no row numbers, so
    /// it keeps no cursor and looks back over no window.
    public static let whatsAppWeb = SourceDescriptor(
        key: "whatsapp.web", aliases: [], consent: .whatsapp, grammar: whatsAppGrammar, retention: .chat,
        obtainedBy: .domText, editWindow: 0, fallbackFor: whatsAppChat.key)
}

/// The sources this build knows. A source starts only when a machine names it.
public enum SourceRegistry {
    public static let all: [SourceDescriptor] = [.whatsAppChat, .whatsAppWeb]

    /// Whether `descriptor` may write a chat now, given the keys of the sources that can read it now. A source that
    /// stands in for another writes only when that other cannot read.
    public static func mayWrite(_ descriptor: SourceDescriptor, whileReadable readable: Set<String>) -> Bool {
        descriptor.fallbackFor.map { !readable.contains($0) } ?? true
    }

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
