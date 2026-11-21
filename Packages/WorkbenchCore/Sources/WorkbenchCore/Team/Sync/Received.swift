import CryptoKit
import Foundation

/// Everything one read of a transport gave: the things that passed every check, and counts of what did not.
public struct Received: Sendable {
    public struct Item: Sendable {
        public var thing: SharedThing
        public var author: Roster.Member
        public var lamport: Int
        public var id: String
    }

    /// The key this person made for one audience set, kept to send more to the same set.
    struct SendingKey: Sendable {
        var group: String
        var key: SymmetricKey
    }

    /// Every verified and opened thing, in Lamport order (ties by author, then id).
    public var items: [Item] = []
    public var roster: Roster
    /// Letters thrown out: junk, a bad signature, an author who is not a member, a thing in another's name.
    public var unverified = 0
    /// Verified envelopes sealed for a group this person is not in. Nothing is wrong: they are not the audience.
    public var undecryptable = 0
    /// For each author's name, the sequence numbers missing below their highest: dropped, or not yet arrived.
    public var gaps: [String: [Int]] = [:]
    var lamport = 0
    var sequences: [String: Int] = [:]
    var sending: [String: SendingKey] = [:]

    init(roster: Roster) { self.roster = roster }

    /// Work events, in Lamport order.
    public var events: [WorkEvent] {
        items.compactMap { if case .event(let event) = $0.thing { event } else { nil } }
    }

    public var days: [SharedDay] { latest { if case .day(let day) = $0.thing { day } else { nil } } }
    public var machines: [SharedMachine] {
        latest { if case .machine(let machine) = $0.thing { machine } else { nil } }
    }
    public var reviews: [MachineReview] { latest { if case .review(let review) = $0.thing { review } else { nil } } }

    /// The newest version of each shared day, machine or review that its author has not withdrawn, newest first.
    private func latest<T>(_ pick: (Item) -> T?) -> [T] {
        var newest: [String: Item] = [:]
        for item in items where !item.isEvent {
            let slot = item.author.card.fingerprint + "/" + item.thing.key
            if let held = newest[slot], (held.lamport, held.id) > (item.lamport, item.id) { continue }
            newest[slot] = item
        }
        return newest.values.sorted { ($0.lamport, $0.id) > ($1.lamport, $1.id) }.compactMap(pick)
    }
}

extension Received.Item {
    fileprivate var isEvent: Bool {
        if case .event = thing { true } else { false }
    }
}
