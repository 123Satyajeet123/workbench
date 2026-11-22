// Source: ports judgment-pilot Packages/WorkbenchCore/Sources/WorkbenchCore/Team/Sync/PersonKeys.swift:4-61 (Ed25519 key
// card and private key) onto swift-crypto, with the device id widened to 16 bytes (research 45 §4).

import Crypto

/// The signature schemes an event header may name. Only Ed25519 exists today; P-256 (Secure Enclave) gets the next
/// value when a device needs it.
public enum SignatureAlgorithm: UInt8, Sendable {
    case ed25519 = 1
}

/// A device, named by the first 16 bytes of SHA-256 over its signature scheme and public key.
public struct DeviceID: FixedBytes {
    public static let count = 16
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.count else { return nil }
        self.bytes = bytes
    }

    fileprivate init(truncating digest: Digest) { bytes = Array(digest.bytes.prefix(Self.count)) }
}

/// The public half of a device's signing key.
public struct DevicePublicKey: Hashable, Sendable {
    public let algorithm: SignatureAlgorithm
    public let rawRepresentation: [UInt8]

    public init(ed25519 rawRepresentation: [UInt8]) throws(EventError) {
        guard (try? Curve25519.Signing.PublicKey(rawRepresentation: rawRepresentation)) != nil else {
            throw .malformed
        }
        algorithm = .ed25519
        self.rawRepresentation = rawRepresentation
    }

    public var id: DeviceID {
        DeviceID(truncating: .framed("workbench.device.v1", [[algorithm.rawValue], rawRepresentation]))
    }

    func verifies(_ signature: [UInt8], over message: [UInt8]) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: rawRepresentation) else { return false }
        return key.isValidSignature(signature, for: message)
    }
}

/// A device's private signing key. The app keeps `rawRepresentation` in secure key storage and nowhere else.
public struct DeviceSigningKey: Sendable {
    private let key: Curve25519.Signing.PrivateKey

    public init() { key = Curve25519.Signing.PrivateKey() }

    public init(rawRepresentation: [UInt8]) throws(EventError) {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation) else {
            throw .malformed
        }
        self.key = key
    }

    public var rawRepresentation: [UInt8] { Array(key.rawRepresentation) }

    public var publicKey: DevicePublicKey {
        DevicePublicKey(ed25519Key: key.publicKey)
    }

    func sign(_ message: [UInt8]) throws(EventError) -> [UInt8] {
        guard let signature = try? key.signature(for: message) else { throw .signingFailed }
        return Array(signature)
    }
}

extension DevicePublicKey {
    fileprivate init(ed25519Key key: Curve25519.Signing.PublicKey) {
        algorithm = .ed25519
        rawRepresentation = Array(key.rawRepresentation)
    }
}
