import CryptoKit
import Foundation

/// The public half of one person's keys. Teammates compare its fingerprint once, by call or in person.
public struct KeyCard: Codable, Sendable, Equatable, Hashable {
    public var signing: Data
    public var agreement: Data

    public init(signing: Data, agreement: Data) {
        self.signing = signing
        self.agreement = agreement
    }

    /// Ten bytes of SHA-256 over both keys, as 20 hex digits. It names the card in envelopes.
    public var fingerprint: String {
        SHA256.hash(data: signing + agreement).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    /// The fingerprint in groups of four digits, to read aloud.
    public var spoken: String {
        let digits = Array(fingerprint)
        return stride(from: 0, to: digits.count, by: 4).map { String(digits[$0..<min($0 + 4, digits.count)]) }
            .joined(separator: " ")
    }

    func verifies(_ signature: Data, over message: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: signing) else { return false }
        return key.isValidSignature(signature, for: message)
    }

    var agreementKey: Curve25519.KeyAgreement.PublicKey? {
        try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: agreement)
    }
}

/// One person's private keys: Ed25519 to sign, X25519 to receive group keys. The app keeps them in the Keychain as
/// `raw`, and nowhere else.
public struct PersonKeys: Sendable {
    private let signing: Curve25519.Signing.PrivateKey
    let agreement: Curve25519.KeyAgreement.PrivateKey

    public init() {
        signing = Curve25519.Signing.PrivateKey()
        agreement = Curve25519.KeyAgreement.PrivateKey()
    }

    /// Reads back what `raw` wrote: 32 bytes of signing key, then 32 bytes of agreement key.
    public init(raw: Data) throws {
        guard raw.count == 64 else { throw SyncError.badKeys }
        signing = try Curve25519.Signing.PrivateKey(rawRepresentation: raw.prefix(32))
        agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw.suffix(32))
    }

    public var raw: Data { signing.rawRepresentation + agreement.rawRepresentation }

    public var card: KeyCard {
        KeyCard(signing: signing.publicKey.rawRepresentation, agreement: agreement.publicKey.rawRepresentation)
    }

    func sign(_ message: Data) throws -> Data { try signing.signature(for: message) }
}

/// Why a team step failed. Each case says what the person can do.
public enum SyncError: Error, LocalizedError, Equatable {
    case badKeys
    case notAMember
    case notTheFounder
    case unknownAudience(String)
    case malformed

    public var errorDescription: String? {
        switch self {
        case .badKeys: "The saved team keys are damaged."
        case .notAMember: "The founder has not confirmed your fingerprint yet."
        case .notTheFounder: "Only the founder can add or remove people."
        case .unknownAudience(let name): "\(name) has no confirmed key, so nothing can be sent to them."
        case .malformed: "The data is not in the expected form."
        }
    }
}

/// Length-prefixed parts under a domain tag: no two different part lists give the same bytes, so a signature over
/// them cannot be moved to another field layout.
enum Framing {
    static func bytes(_ domain: String, _ parts: [Data]) -> Data {
        ([Data(domain.utf8)] + parts).reduce(into: Data()) { out, part in
            withUnsafeBytes(of: UInt32(part.count).bigEndian) { out.append(contentsOf: $0) }
            out.append(part)
        }
    }

    static func bytes(_ domain: String, _ parts: [String]) -> Data { bytes(domain, parts.map { Data($0.utf8) }) }
}
