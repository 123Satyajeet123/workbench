import Foundation

/// Where in a message a line is: the attached file and the page of a deck. A message line has none.
struct MailPlace: Codable, Equatable {
    var file: String
    var page: Int
}

/// One line of a Gmail thread the person opened, as the app reads it from the evidence store: a message, or one page of
/// a deck attached to a message. It holds what the store holds for the line, with the label and authority the writer
/// gave it. Only a label the person named is ever stored.
public struct MailPart: Equatable, Sendable {
    /// The row number of the evidence line: the number a model cites.
    public var id: Int64?
    public var lineID: Data?
    /// Who may read the line and how far it is trusted, as the store recorded them. Nil when the store's label is not
    /// the label of the line's source.
    public var provenance: Provenance?
    public var threadID: String
    /// The Gmail label the person named.
    public var label: String
    /// `me` for the person's own mail, else the sender's address; nil when the page showed none.
    public var sender: String?
    /// The attached file of a deck page; empty for a message.
    public var name: String
    /// Counts from 1 for a deck page; 0 for a message.
    public var page: Int
    public var sentAt: Date
    public var text: String

    public init(
        id: Int64? = nil, lineID: Data? = nil, provenance: Provenance? = nil, threadID: String, label: String,
        sender: String?, name: String = "", page: Int = 0, sentAt: Date, text: String
    ) {
        self.id = id
        self.lineID = lineID
        self.provenance = provenance
        self.threadID = threadID
        self.label = label
        self.sender = sender
        self.name = name
        self.page = page
        self.sentAt = sentAt
        self.text = text
    }

    public var isDeck: Bool { page > 0 }

    /// The words were quoted from an earlier message, as the page marked them.
    public var isQuoted: Bool { provenance?.authority == .forwardedOrQuoted }
}

extension MailPart {
    /// The part a stored line is. Nil for a line that is no mail line of a named label: a tombstone, or a grant that is
    /// not a mail grant.
    init?(_ line: StoredLine) {
        let prefix = Store.grantID(kind: .mail, label: "")
        guard !line.isTombstone, line.grantID.hasPrefix(prefix) else { return nil }
        let place = line.coordinate.flatMap { try? Coding.value(MailPlace.self, from: $0) }
        self.init(
            id: line.number, lineID: line.lineID, provenance: line.provenance, threadID: line.container,
            label: String(line.grantID.dropFirst(prefix.count)), sender: line.actor, name: place?.file ?? "",
            page: place?.page ?? 0, sentAt: line.time ?? .distantPast, text: line.text)
    }
}
