import Foundation
import Kernel
import Lines

/// The app's work for the WhatsApp Web page the browser extension reads. It writes the same evidence lines as the
/// store reader, through the same writer: the entity key is the chat and the stanza id from the page's `data-id`.
/// The web page is the fallback for a Mac without Full Disk Access, so it writes a chat only while the store reader
/// cannot read it (`SourceRegistry.mayWrite`). It is also a container source: while the person has the chooser open it
/// takes the chat that is open in the page (`see`), and keeps it in memory on the board.
public struct WhatsAppWebIntake: Sendable {
    public static let readerVersion = "whatsapp-web 1"

    enum Refusal: Error, Equatable {
        case noOwner
        /// The store reader reads this chat, so the web page writes none of it.
        case storeReaderReads
        /// A group needs a member list from the group-info panel, and the page gave none that proves one.
        case groupAudienceUnknown
        case chatNotAllowed
        /// The person is not looking for a chat to choose, so the page's chat is not taken.
        case chooserClosed
        case notWhatsAppWeb
        case unrecognizedChat
        case unusableTitle
    }

    public var owner: Result<PersonID, any Error>
    /// The keys of the sources that can read their chats now.
    public var readableSources: @Sendable () -> Set<String>
    /// The chats the page showed while the person asked, in memory only.
    public let board: SightingBoard
    private let zone: TimeZone

    public init(
        owner: Result<PersonID, any Error>, readableSources: @escaping @Sendable () -> Set<String>,
        board: SightingBoard = SightingBoard(descriptor: .whatsAppWeb), zone: TimeZone = .current
    ) {
        self.owner = owner
        self.readableSources = readableSources
        self.board = board
        self.zone = zone
    }

    /// Writes nothing: the person has no owner identity yet, and the store reader is taken to read.
    public static let refusing = WhatsAppWebIntake(
        owner: .failure(Refusal.noOwner), readableSources: { [SourceDescriptor.whatsAppChat.key] })

    /// The chats the extension may read now (none while the store reader reads), and whether it may tell the app which
    /// chat is open.
    func status(store: Store) throws -> PageHost.Reply {
        let discover = board.isOpen
        guard SourceRegistry.mayWrite(.whatsAppWeb, whileReadable: readableSources()) else {
            return PageHost.Reply(kept: false, chats: [], discover: discover)
        }
        let policy = try store.currentPolicy()
        let now = store.clock()
        let chats = (policy.allowList[.whatsapp] ?? []).filter {
            policy.authorize(CaptureRequest(kind: .whatsapp, label: $0), at: now).grant != nil
        }
        return PageHost.Reply(kept: false, chats: chats.map(WhatsAppJID.canonical).sorted(), discover: discover)
    }

    /// Takes the chat that is open in the page as a sighting, while the person has the chooser open. It writes nothing
    /// to the store: the chat is chosen, or not, by the person.
    func see(_ page: WhatsAppChatSeen, now: Date) throws -> PageHost.Reply {
        guard WhatsAppWebPage.isWhatsAppWeb(browser: page.browser, url: page.url) else { throw Refusal.notWhatsAppWeb }
        guard let id = Self.chatID(page.chat) else { throw Refusal.unrecognizedChat }
        let title = page.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf16.count <= WhatsAppChatSeen.maximumTitle else { throw Refusal.unusableTitle }
        let kind: ContainerKind = WhatsAppJID.isGroup(id) ? .group : .direct
        let sighting = ContainerSighting(
            container: Container(id: id, kind: kind, title: title), source: SourceDescriptor.whatsAppWeb.key,
            observedAt: now, membership: kind == .group ? page.members?.membership() : nil)
        guard board.record(sighting) else { throw Refusal.chooserClosed }
        return PageHost.Reply(kept: false)
    }

    /// Keeps the messages of one allowed chat. The write transaction checks the consent again. A group is kept only
    /// with a member list that the group-info panel proved in this same message.
    func keep(_ snapshot: WhatsAppWebSnapshot, store: Store) throws -> PageHost.Reply {
        let (chat, messages) = try snapshot.checked()
        guard SourceRegistry.mayWrite(.whatsAppWeb, whileReadable: readableSources()) else {
            throw Refusal.storeReaderReads
        }
        let policy = try store.currentPolicy()
        guard let label = Self.allowedLabel(of: chat, in: policy),
            let grant = policy.authorize(CaptureRequest(kind: .whatsapp, label: label), at: store.clock()).grant
        else { throw Refusal.chatNotAllowed }
        let owner = try owner.get()
        let kind: ContainerKind = WhatsAppJID.isGroup(chat) ? .group : .direct
        guard
            let audience = AudienceRule.digest(
                of: Container(id: chat, kind: kind, title: label), owner: WhatsAppAudience.owner,
                membership: snapshot.members?.membership())
        else {
            board.wait(on: chat, words: SourceDescriptor.whatsAppWeb.membershipHowTo ?? "")
            throw Refusal.groupAudienceUnknown
        }
        board.stopWaiting(on: chat)
        let times = WebSentStamp.instants(messages.map(\.sent), in: zone)
        let lines = try zip(messages, times).map { try Self.line($0, at: $1, in: chat) }
        let reading = SourceReading(
            grant: grant, label: label, container: chat, audience: audience, lines: lines, cursorAfter: nil,
            readerVersion: Self.readerVersion)
        let report = try store.record(reading, of: .whatsAppWeb, owner: owner)
        return PageHost.Reply(kept: report.inserted + report.tombstones > 0)
    }

    /// The canonical id of a chat the page named, or nil when it is not a chat id.
    private static func chatID(_ text: String) -> String? {
        guard text.utf8.count <= 64,
            text.wholeMatch(of: #/[0-9]+(?:-[0-9]+)?@(?:c\.us|s\.whatsapp\.net|g\.us|lid)/#) != nil
        else { return nil }
        return WhatsAppJID.canonical(text)
    }

    /// The allow-list entry that names this chat, whatever form of its id the person's list holds.
    private static func allowedLabel(of chat: String, in policy: CapturePolicy) -> String? {
        (policy.allowList[.whatsapp] ?? []).sorted().first { WhatsAppJID.canonical($0) == chat }
    }

    private static func line(_ message: WhatsAppWebSnapshot.Checked, at time: UTCInstant?, in chat: String) throws
        -> ObservedLine
    {
        let key = try entityKey(of: message.id, in: chat)
        return ObservedLine(
            line: message.text.map { Line(entity: key, text: $0, readerVersion: readerVersion) }
                ?? .tombstone(entity: key, readerVersion: readerVersion),
            eventTime: time, actor: message.id.fromMe ? WhatsAppAudience.owner : message.id.sender ?? chat,
            messageRef: message.id.stanza)
    }

    private static func entityKey(of id: WebMessageID, in chat: String) throws -> EntityKey {
        guard WhatsAppJID.isGroup(chat) else {
            return try .whatsAppDirect(chat: chat, fromMe: id.fromMe, stanzaID: id.stanza)
        }
        guard let author = id.groupAuthor else { throw WebSnapshotError.senderUnknown }
        return try .whatsAppGroup(chat: chat, author: author, stanzaID: id.stanza)
    }
}

extension WhatsAppWebIntake: ContainerSource {
    public var descriptor: SourceDescriptor { .whatsAppWeb }

    public func sightings(policy: CapturePolicy, now: Date) -> [ContainerSighting] {
        board.sightings(policy: policy, now: now)
    }
}
