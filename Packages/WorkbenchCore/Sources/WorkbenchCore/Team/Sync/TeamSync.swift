import CryptoKit
import Foundation

/// One person's side of team sync over any `Transport`: seals what they share, reads what others shared, and runs the
/// membership steps. It holds no state of its own: roster, keys and sequence numbers are all read back from the
/// transport, so a Mac that starts again, or a second Mac, finds them.
public struct TeamSync: Sendable {
    /// What a publish did: letters sent, and things kept on this Mac because a reader has no confirmed key.
    public struct Outcome: Sendable, Equatable {
        public var sent = 0
        public var held = 0
    }

    let transport: any Transport
    let keys: PersonKeys
    /// This person's name in the team.
    public let name: String
    /// The one person whose signature decides who is a member. This Mac trusts them because the person compared
    /// their fingerprint by call or in person.
    public let founder: Roster.Member

    public init(transport: any Transport, keys: PersonKeys, name: String, founder: Roster.Member) {
        self.transport = transport
        self.keys = keys
        self.name = name
        self.founder = founder
    }

    public var isFounder: Bool { keys.card == founder.card }

    /// Seals each thing for its audience and puts it on the transport. A thing whose audience has a person with no
    /// confirmed key is not sent: it fails closed and stays on this Mac. A thing sent before is not sent again.
    @discardableResult
    public func publish(_ things: [SharedThing]) throws -> Outcome {
        var state = try receive()
        guard let me = state.roster.member(keys.card.fingerprint) else { throw SyncError.notAMember }
        var sent = Set(state.items.filter { $0.author == me }.compactMap { try? $0.thing.encoded() })
        var outcome = Outcome()
        for thing in things {
            let plaintext = try thing.encoded()
            guard sent.insert(plaintext).inserted else { continue }
            guard let readers = try? readers(of: thing, roster: state.roster, me: me) else {
                outcome.held += 1
                continue
            }
            let key = try sendingKey(for: readers, state: &state)
            let sequence = (state.sequences[me.card.fingerprint] ?? 0) + 1
            let lamport = thing.clock ?? state.lamport + 1
            state.sequences[me.card.fingerprint] = sequence
            state.lamport = max(state.lamport, lamport)
            let envelope = try Envelope(
                sealing: plaintext, sequence: sequence, lamport: lamport, group: key.group, key: key.key, author: keys)
            try transport.put(try Self.letter(.envelope, envelope.id, envelope))
            outcome.sent += 1
        }
        return outcome
    }

    /// Everyone the thing goes to: its audience, or the whole team; always its author.
    private func readers(of thing: SharedThing, roster: Roster, me: Roster.Member) throws -> [KeyCard] {
        guard let names = thing.audience else { return roster.members.map(\.card) }
        let cards = try names.flatMap { person in
            let found = roster.cards(named: person)
            guard !found.isEmpty else { throw SyncError.unknownAudience(person) }
            return found
        }
        return Array(Set(cards + [me.card]))
    }

    /// The key this person made for the set of `readers`, made and handed out when there is none yet.
    private func sendingKey(for readers: [KeyCard], state: inout Received) throws -> Received.SendingKey {
        let set = GroupKey.set(of: readers)
        if let held = state.sending[set] { return held }
        let made = Received.SendingKey(group: GroupKey.newName(for: readers), key: SymmetricKey(size: .bits256))
        for grant in try KeyGrant.grants(for: made.key, group: made.group, members: readers, from: keys) {
            try transport.put(try Self.letter(.grant, grant.id, grant))
        }
        state.sending[set] = made
        return made
    }

    static func letter<T: Encodable>(_ kind: Letter.Kind, _ id: String, _ value: T) throws -> Letter {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return Letter(kind: kind, id: id, body: try encoder.encode(value))
    }
}
