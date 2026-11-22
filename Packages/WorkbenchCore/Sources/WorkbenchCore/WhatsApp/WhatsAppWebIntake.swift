import Foundation
import Kernel
import Lines

/// The app's work for the WhatsApp Web page the browser extension reads. It writes the same evidence lines as the
/// store reader, through the same writer: the entity key is the chat and the stanza id from the page's `data-id`.
/// The web page is the fallback for a Mac without Full Disk Access, so it writes a chat only while the store reader
/// cannot read it (`SourceRegistry.mayWrite`).
public struct WhatsAppWebIntake: Sendable {
    public static let readerVersion = "whatsapp-web 1"

    enum Refusal: Error, Equatable {
        case noOwner
        /// The store reader reads this chat, so the web page writes none of it.
        case storeReaderReads
        /// The page gives no list of the members of a group, so no audience can be named.
        case groupAudienceUnknown
        case chatNotAllowed
    }

    public var owner: Result<PersonID, any Error>
    /// The keys of the sources that can read their chats now.
    public var readableSources: @Sendable () -> Set<String>
    private let zone: TimeZone

    public init(
        owner: Result<PersonID, any Error>, readableSources: @escaping @Sendable () -> Set<String>,
        zone: TimeZone = .current
    ) {
        self.owner = owner
        self.readableSources = readableSources
        self.zone = zone
    }

    /// Writes nothing: the person has no owner identity yet, and the store reader is taken to read.
    public static let refusing = WhatsAppWebIntake(
        owner: .failure(Refusal.noOwner), readableSources: { [SourceDescriptor.whatsAppChat.key] })

    /// The chats the extension may read now: the allowed one-to-one chats, and none while the store reader reads.
    func status(store: Store) throws -> PageHost.Reply {
        guard SourceRegistry.mayWrite(.whatsAppWeb, whileReadable: readableSources()) else {
            return PageHost.Reply(kept: false, chats: [])
        }
        let policy = try store.currentPolicy()
        let now = store.clock()
        let chats = (policy.allowList[.whatsapp] ?? []).filter {
            !WhatsAppJID.isGroup(WhatsAppJID.canonical($0))
                && policy.authorize(CaptureRequest(kind: .whatsapp, label: $0), at: now).grant != nil
        }
        return PageHost.Reply(kept: false, chats: chats.map(WhatsAppJID.canonical).sorted())
    }

    /// Keeps the messages of one allowed one-to-one chat. The write transaction checks the consent again.
    func keep(_ snapshot: WhatsAppWebSnapshot, store: Store) throws -> PageHost.Reply {
        let (chat, messages) = try snapshot.checked()
        guard SourceRegistry.mayWrite(.whatsAppWeb, whileReadable: readableSources()) else {
            throw Refusal.storeReaderReads
        }
        guard !WhatsAppJID.isGroup(chat) else { throw Refusal.groupAudienceUnknown }
        let policy = try store.currentPolicy()
        guard let label = Self.allowedLabel(of: chat, in: policy),
            let grant = policy.authorize(CaptureRequest(kind: .whatsapp, label: label), at: store.clock()).grant
        else { throw Refusal.chatNotAllowed }
        let owner = try owner.get()
        let times = WebSentStamp.instants(messages.map(\.sent), in: zone)
        let lines = try zip(messages, times).map { try Self.line($0, at: $1, in: chat) }
        let reading = SourceReading(
            grant: grant, label: label, container: chat,
            audience: AudienceDigest(owner: WhatsAppAudience.owner, members: [chat]), lines: lines, cursorAfter: nil,
            readerVersion: Self.readerVersion)
        let report = try store.record(reading, of: .whatsAppWeb, owner: owner)
        return PageHost.Reply(kept: report.inserted + report.tombstones > 0)
    }

    /// The allow-list entry that names this chat, whatever form of its id the person's list holds.
    private static func allowedLabel(of chat: String, in policy: CapturePolicy) -> String? {
        (policy.allowList[.whatsapp] ?? []).sorted().first { WhatsAppJID.canonical($0) == chat }
    }

    private static func line(_ message: WhatsAppWebSnapshot.Checked, at time: UTCInstant?, in chat: String) throws
        -> ObservedLine
    {
        let key = try EntityKey.whatsAppDirect(chat: chat, fromMe: message.id.fromMe, stanzaID: message.id.stanza)
        return ObservedLine(
            line: message.text.map { Line(entity: key, text: $0, readerVersion: readerVersion) }
                ?? .tombstone(entity: key, readerVersion: readerVersion),
            eventTime: time, actor: message.id.fromMe ? WhatsAppAudience.owner : chat, messageRef: message.id.stanza)
    }
}
