import Foundation

/// One signed act on who is in the team. The subject's card travels in it.
/// - `hello`: the subject says who they are, signed with their own key. It proves nothing until the founder confirms
///   the fingerprint by call or in person.
/// - `admit` and `remove`: the founder's decision, signed with the founder's key.
public struct MembershipEvent: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case hello, admit, remove }

    public var id: String
    public var lamport: Int
    public var kind: Kind
    public var subject: String
    public var card: KeyCard
    /// The signer's fingerprint.
    public var author: String
    public var signature: Data

    public init(kind: Kind, subject: String, card: KeyCard, lamport: Int, signedBy keys: PersonKeys) throws {
        id = UUID().uuidString
        self.lamport = lamport
        self.kind = kind
        self.subject = subject
        self.card = card
        author = keys.card.fingerprint
        signature = Data()
        signature = try keys.sign(signedBytes)
    }

    private var signedBytes: Data {
        Framing.bytes(
            "workbench.member.v1",
            [
                Data(id.utf8), Data(String(lamport).utf8), Data(kind.rawValue.utf8), Data(subject.utf8), card.signing,
                card.agreement, Data(author.utf8),
            ])
    }

    func isSigned(by signer: KeyCard) -> Bool {
        signer.fingerprint == author && signer.verifies(signature, over: signedBytes)
    }

    /// A hello checks against the key it carries: the subject signed their own card.
    var isSelfSigned: Bool { kind == .hello && isSigned(by: card) }
}

/// Who counts as a member, as one Mac works it out from the membership events and the one founder it trusts.
/// A person counts only after the founder's signed `admit`; a later `remove` ends it. The folder cannot add a person:
/// an admit that the founder's key did not sign is thrown out and counted.
public struct Roster: Sendable, Equatable {
    public struct Member: Codable, Sendable, Equatable, Hashable {
        public var name: String
        public var card: KeyCard

        public init(name: String, card: KeyCard) {
            self.name = name
            self.card = card
        }
    }

    public let founder: Member
    public private(set) var members: [Member]
    /// People who announced themselves and wait for the founder's confirmation, newest hello per person.
    public private(set) var waiting: [MembershipEvent] = []
    /// Events thrown out: bad signature, or a decision the founder did not sign.
    public private(set) var rejected = 0
    /// The highest clock in any event kept.
    public private(set) var lamport = 0

    public init(_ events: [MembershipEvent], founder: Member) {
        self.founder = founder
        var standing = [founder.card.fingerprint: founder]
        var hellos: [String: MembershipEvent] = [:]
        let unique = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        for event in unique.sorted(by: { ($0.lamport, $0.id) < ($1.lamport, $1.id) }) {
            switch event.kind {
            case .hello where event.isSelfSigned:
                hellos[event.card.fingerprint] = event
            case .admit where event.isSigned(by: founder.card):
                standing[event.card.fingerprint] = Member(name: event.subject, card: event.card)
            case .remove where event.isSigned(by: founder.card) && event.card != founder.card:
                standing[event.card.fingerprint] = nil
            default:
                rejected += 1
                continue
            }
            lamport = max(lamport, event.lamport)
        }
        members = standing.values.sorted { ($0.name, $0.card.fingerprint) < ($1.name, $1.card.fingerprint) }
        waiting = hellos.values.filter { standing[$0.card.fingerprint] == nil }.sorted { $0.subject < $1.subject }
    }

    public func member(_ fingerprint: String) -> Member? { members.first { $0.card.fingerprint == fingerprint } }

    /// Every card of the person with this name: more than one when they use more than one Mac.
    public func cards(named name: String) -> [KeyCard] { members.filter { $0.name == name }.map(\.card) }
}
