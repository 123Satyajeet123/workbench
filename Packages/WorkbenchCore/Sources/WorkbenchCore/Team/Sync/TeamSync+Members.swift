import Foundation

extension TeamSync {
    /// Says who this person is, signed with their own key. Once only. It lets no one read anything: the founder must
    /// confirm the fingerprint before this person counts.
    public static func announce(name: String, keys: PersonKeys, on transport: any Transport) throws {
        let existing = try announcements(on: transport)
        guard !existing.contains(where: { $0.card == keys.card }) else { return }
        let hello = try MembershipEvent(kind: .hello, subject: name, card: keys.card, lamport: 1, signedBy: keys)
        try transport.put(try letter(.roster, hello.id, hello))
    }

    /// The people who announced themselves, one hello per card. Each is signed by its own card only, so the
    /// fingerprint, compared out loud, is what makes it trustworthy.
    public static func announcements(on transport: any Transport) throws -> [MembershipEvent] {
        let hellos = try transport.list(after: nil).letters.filter { $0.kind == .roster }.compactMap {
            try? JSONDecoder().decode(MembershipEvent.self, from: $0.body)
        }
        let valid = hellos.filter(\.isSelfSigned)
        return Array(Dictionary(valid.map { ($0.card, $0) }, uniquingKeysWith: { first, _ in first }).values)
            .sorted { ($0.subject, $0.card.fingerprint) < ($1.subject, $1.card.fingerprint) }
    }

    /// The founder confirms a fingerprint: the person counts from here, and is in the sets of later sends.
    public func admit(_ hello: MembershipEvent) throws {
        guard hello.isSelfSigned else { throw SyncError.malformed }
        try decide(.admit, Roster.Member(name: hello.subject, card: hello.card))
    }

    /// The founder removes a person. Later sends are sealed under keys the person never gets; what they already
    /// read stays read.
    public func remove(_ member: Roster.Member) throws { try decide(.remove, member) }

    private func decide(_ kind: MembershipEvent.Kind, _ member: Roster.Member) throws {
        guard isFounder else { throw SyncError.notTheFounder }
        let event = try MembershipEvent(
            kind: kind, subject: member.name, card: member.card, lamport: try receive().lamport + 1, signedBy: keys)
        try transport.put(try Self.letter(.roster, event.id, event))
    }
}
