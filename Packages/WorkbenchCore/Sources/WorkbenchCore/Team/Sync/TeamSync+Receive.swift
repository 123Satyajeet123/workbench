import CryptoKit
import Foundation

extension TeamSync {
    /// Reads every letter and keeps what passes, in this order: the roster from the founder's signatures; the group
    /// keys wrapped for this person; then each envelope must be signed by a current member, open under a held key,
    /// and hold a thing in its signer's own name. Anything else is dropped and counted. The result does not depend on
    /// the order letters arrive in, or on duplicates.
    public func receive() throws -> Received {
        let letters = try transport.list(after: nil).letters
        var junk = 0
        let members = decode(MembershipEvent.self, in: letters, .roster, junk: &junk)
        var received = Received(roster: Roster(members, founder: founder))
        received.unverified = junk + received.roster.rejected
        received.lamport = received.roster.lamport
        let held = unwrapKeys(from: letters, into: &received)
        var junkEnvelopes = 0
        let envelopes = verified(decode(Envelope.self, in: letters, .envelope, junk: &junkEnvelopes), &received)
        received.unverified += junkEnvelopes
        open(envelopes, with: held, into: &received)
        return received
    }

    private func decode<T: Decodable>(_ type: T.Type, in letters: [Letter], _ kind: Letter.Kind, junk: inout Int) -> [T]
    {
        letters.filter { $0.kind == kind }.compactMap {
            if let value = try? JSONDecoder().decode(type, from: $0.body) { return value }
            junk += 1
            return nil
        }
    }

    /// The keys wrapped for this person by a current member. A grant this person made is also a sending key.
    private func unwrapKeys(from letters: [Letter], into received: inout Received) -> [String: [SymmetricKey]] {
        var junk = 0
        var held: [String: [SymmetricKey]] = [:]
        let mine = keys.card.fingerprint
        for grant in decode(KeyGrant.self, in: letters, .grant, junk: &junk) where grant.recipient == mine {
            guard let sender = received.roster.member(grant.sender),
                let key = try? grant.open(from: sender.card, with: keys)
            else {
                junk += 1
                continue
            }
            held[grant.group, default: []].append(key)
            if grant.sender == mine {
                received.sending[String(grant.group.prefix { $0 != "." })] = .init(group: grant.group, key: key)
            }
        }
        received.unverified += junk
        return held
    }

    /// Envelopes signed by a current member, once each. Two different envelopes under one id (an author who wrote
    /// two, or a copy with a changed field) keep the one with the smaller signature, so every Mac keeps the same.
    private func verified(_ envelopes: [Envelope], _ received: inout Received) -> [Envelope] {
        var kept: [String: Envelope] = [:]
        for envelope in envelopes {
            guard let author = received.roster.member(envelope.author), envelope.isSigned(by: author.card) else {
                received.unverified += 1
                continue
            }
            guard let held = kept[envelope.id], held != envelope else {
                kept[envelope.id] = envelope
                continue
            }
            received.unverified += 1
            if envelope.signature.lexicographicallyPrecedes(held.signature) { kept[envelope.id] = envelope }
        }
        return kept.values.sorted { ($0.lamport, $0.author, $0.id) < ($1.lamport, $1.author, $1.id) }
    }

    private func open(_ envelopes: [Envelope], with held: [String: [SymmetricKey]], into received: inout Received) {
        var present: [String: Set<Int>] = [:]
        for envelope in envelopes {
            guard let sequence = envelope.sequence, let author = received.roster.member(envelope.author) else {
                continue
            }
            present[author.name, default: []].insert(sequence)
            received.lamport = max(received.lamport, envelope.lamport)
            if envelope.author == keys.card.fingerprint {
                received.sequences[envelope.author] = max(received.sequences[envelope.author] ?? 0, sequence)
            }
            guard let candidates = held[envelope.group] else {
                received.undecryptable += 1
                continue
            }
            guard
                let thing = candidates.lazy.compactMap({ try? envelope.open(with: $0) }).compactMap({
                    try? SharedThing(decoding: $0)
                }).first,
                thing.author == author.name
            else {
                received.unverified += 1
                continue
            }
            received.items.append(.init(thing: thing, author: author, lamport: envelope.lamport, id: envelope.id))
        }
        for (name, sequences) in present {
            let missing = (1...(sequences.max() ?? 0)).filter { !sequences.contains($0) }
            if !missing.isEmpty { received.gaps[name] = missing }
        }
    }
}
