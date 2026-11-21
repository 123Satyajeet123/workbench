import CryptoKit
import Foundation

/// A symmetric key for one audience: the set of people who may read one source, as the audience rule computes it.
/// The group name is `<set>.<key id>`. `set` is a digest of the members' fingerprints, so a changed set is a new group
/// with a new key; that is how adding or removing a person rotates the key for later events. The key id tells apart
/// the keys that different authors make for the same set.
public enum GroupKey {
    public static func set(of members: [KeyCard]) -> String { digest(Set(members.map(\.fingerprint)).sorted()) }

    static func digest(_ sortedPrints: [String]) -> String {
        SHA256.hash(data: Data(sortedPrints.joined(separator: ",").utf8)).prefix(8).map { String(format: "%02x", $0) }
            .joined()
    }

    public static func newName(for members: [KeyCard]) -> String {
        let id = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        return set(of: members) + "." + id
    }
}

/// A group key wrapped for one member. HPKE (RFC 9180, in CryptoKit) does the X25519 exchange, the HKDF and the
/// ChaCha20-Poly1305 wrap. The sender signs the grant, so a reader knows who handed out the key.
public struct KeyGrant: Codable, Sendable, Equatable, Identifiable {
    public var group: String
    /// The fingerprints of everyone the key goes to. Their digest must equal the group's set.
    public var members: [String]
    public var sender: String
    public var recipient: String
    public var encapsulated: Data
    public var wrapped: Data
    public var signature: Data

    public var id: String { group + "." + recipient }

    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    /// One grant for each of `members`; `members` must hold the sender.
    public static func grants(for key: SymmetricKey, group: String, members: [KeyCard], from sender: PersonKeys) throws
        -> [KeyGrant]
    {
        let prints = Set(members.map(\.fingerprint)).sorted()
        return try members.map { member in
            guard let recipientKey = member.agreementKey else { throw SyncError.malformed }
            var hpke = try HPKE.Sender(
                recipientKey: recipientKey, ciphersuite: suite, info: info(group, member.fingerprint))
            let wrapped = try key.withUnsafeBytes { try hpke.seal(Data($0), authenticating: context(group, prints)) }
            var grant = KeyGrant(
                group: group, members: prints, sender: sender.card.fingerprint, recipient: member.fingerprint,
                encapsulated: hpke.encapsulatedKey, wrapped: wrapped, signature: Data())
            grant.signature = try sender.sign(grant.signedBytes)
            return grant
        }
    }

    /// The key, when `sender` signed the grant, the member list matches the group, and `keys` is the recipient.
    public func open(from sender: KeyCard, with keys: PersonKeys) throws -> SymmetricKey {
        let prints = members.sorted()
        guard sender.fingerprint == self.sender, sender.verifies(signature, over: signedBytes),
            recipient == keys.card.fingerprint, prints.contains(recipient), prints.contains(self.sender),
            group.hasPrefix(GroupKey.digest(prints) + ".")
        else { throw SyncError.malformed }
        var hpke = try HPKE.Recipient(
            privateKey: keys.agreement, ciphersuite: Self.suite, info: Self.info(group, recipient),
            encapsulatedKey: encapsulated)
        return SymmetricKey(data: try hpke.open(wrapped, authenticating: Self.context(group, prints)))
    }

    private var signedBytes: Data {
        Framing.bytes(
            "workbench.grant.v1",
            [
                Data(group.utf8), Data(members.joined(separator: ",").utf8), Data(sender.utf8), Data(recipient.utf8),
                encapsulated, wrapped,
            ])
    }

    private static func info(_ group: String, _ recipient: String) -> Data {
        Framing.bytes("workbench.grant.info.v1", [group, recipient])
    }

    private static func context(_ group: String, _ prints: [String]) -> Data {
        Framing.bytes("workbench.grant.aad.v1", [group, prints.joined(separator: ",")])
    }
}
