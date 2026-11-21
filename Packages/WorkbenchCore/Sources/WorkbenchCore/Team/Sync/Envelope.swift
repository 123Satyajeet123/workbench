import CryptoKit
import Foundation

/// One shared thing, signed and sealed. The signature covers every field but itself, so a changed id, clock, author,
/// group, nonce or ciphertext fails verification. The id is `<author fingerprint>.<sequence>`: the sequence counts the
/// author's envelopes, so a reader can see a gap where one was dropped.
public struct Envelope: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var lamport: Int
    public var author: String
    /// The key that sealed it: `<audience set>.<key id>` (see `GroupKey`).
    public var group: String
    public var nonce: Data
    /// The AES-GCM ciphertext followed by its 16-byte tag.
    public var ciphertext: Data
    public var signature: Data

    private static let tagSize = 16

    public static func id(author: String, sequence: Int) -> String { "\(author).\(sequence)" }

    public var sequence: Int? {
        guard id.hasPrefix(author + ".") else { return nil }
        return Int(id.dropFirst(author.count + 1))
    }

    public init(
        sealing plaintext: Data, sequence: Int, lamport: Int, group: String, key: SymmetricKey, author keys: PersonKeys
    ) throws {
        author = keys.card.fingerprint
        id = Self.id(author: author, sequence: sequence)
        self.lamport = lamport
        self.group = group
        let nonce = AES.GCM.Nonce()
        self.nonce = Data(nonce)
        ciphertext = Data()
        signature = Data()
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: header)
        ciphertext = Data(sealed.ciphertext + sealed.tag)
        signature = try keys.sign(signedBytes)
    }

    /// The fields the cipher authenticates: a ciphertext moved under another id or group does not open.
    private var header: Data { Framing.bytes("workbench.envelope.header.v1", [id, String(lamport), author, group]) }

    private var signedBytes: Data { Framing.bytes("workbench.envelope.v1", [header, nonce, ciphertext]) }

    /// True when `card` is the author's card and its key made the signature.
    public func isSigned(by card: KeyCard) -> Bool {
        card.fingerprint == author && sequence != nil && card.verifies(signature, over: signedBytes)
    }

    public func open(with key: SymmetricKey) throws -> Data {
        guard ciphertext.count >= Self.tagSize else { throw SyncError.malformed }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext.dropLast(Self.tagSize),
            tag: ciphertext.suffix(Self.tagSize))
        return try AES.GCM.open(box, using: key, authenticating: header)
    }
}
