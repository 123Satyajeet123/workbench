import Foundation
import Observation
import WorkbenchCore

/// Who this Mac trusts in the team: its own keys (in the Keychain), the founder whose signature decides who is a
/// member, and what the last read of the team folder found. A person counts only after the founder confirmed their
/// fingerprint, compared by call or in person; every other Mac trusts the founder because its person compared
/// the founder's fingerprint once.
@Observable
final class TeamTrustModel {
    private static let keysName = "team.keys"
    private static let founderKey = StateKey<Roster.Member>.json("team.founder")

    private(set) var card: KeyCard
    private(set) var founder: Roster.Member?
    private(set) var members: [Roster.Member] = []
    /// People who announced themselves and wait for a confirmed fingerprint.
    private(set) var waiting: [MembershipEvent] = []
    /// Letters the last read threw out: a bad signature, a stranger, a thing written in another's name.
    private(set) var unverified = 0
    /// Envelopes missing below an author's highest: dropped, or still on their way.
    private(set) var gaps: [String: [Int]] = [:]
    private(set) var problem: String?

    @ObservationIgnored private let keys: PersonKeys
    @ObservationIgnored private let store: Store

    init(store: Store, secrets: SecretStore) {
        self.store = store
        let saved = secrets.read(Self.keysName).flatMap { Data(base64Encoded: $0) }.flatMap { try? PersonKeys(raw: $0) }
        let keys = saved ?? PersonKeys()
        self.keys = keys
        card = keys.card
        if saved == nil {
            do { try secrets.save(keys.raw.base64EncodedString(), as: Self.keysName) } catch {
                problem = "Could not keep your team keys in the Keychain: \(error.localizedDescription)"
            }
        }
        founder = (try? Self.founderKey.load(from: store)) ?? nil
    }

    var isFounder: Bool { founder?.card == card }
    var fingerprint: String { card.spoken }

    /// The sync for this folder, once a founder is known.
    func sync(folder: URL, me: String) -> TeamSync? {
        founder.map { TeamSync(transport: FolderTransport(team: folder), keys: keys, name: me, founder: $0) }
    }

    func announce(folder: URL, me: String) throws {
        try TeamSync.announce(name: me, keys: keys, on: FolderTransport(team: folder))
    }

    func absorb(_ received: Received) {
        members = received.roster.members
        waiting = received.roster.waiting
        unverified = received.unverified
        gaps = received.gaps
    }

    /// Before a founder is known nothing can be verified: only the announcements can be listed.
    func scan(folder: URL) {
        let hellos = (try? TeamSync.announcements(on: FolderTransport(team: folder))) ?? []
        waiting = hellos.filter { $0.card != card }
        (members, unverified, gaps) = ([], 0, [:])
    }

    func becomeFounder(named me: String) { setFounder(.init(name: me, card: card)) }

    /// The person compared this fingerprint out loud. The founder then admits them; on any other Mac, with no
    /// founder yet, they become the founder this Mac trusts.
    func confirm(_ hello: MembershipEvent, with sync: TeamSync?) {
        do {
            if let sync, sync.isFounder {
                try sync.admit(hello)
            } else if founder == nil {
                setFounder(.init(name: hello.subject, card: hello.card))
            }
        } catch {
            problem = "Could not confirm \(hello.subject): \(error.localizedDescription)"
        }
    }

    func remove(_ member: Roster.Member, with sync: TeamSync?) {
        do { try sync?.remove(member) } catch {
            problem = "Could not remove \(member.name): \(error.localizedDescription)"
        }
    }

    func dismissProblem() { problem = nil }

    private func setFounder(_ member: Roster.Member) {
        do {
            try Self.founderKey.save(member, to: store)
            founder = member
        } catch {
            problem = "Could not save the founder: \(error.localizedDescription)"
        }
    }
}
