import CryptoKit
import Foundation

/// One thing a transport carries: opaque bytes with an id and a kind. A transport never reads the bytes.
public struct Letter: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        /// A sealed `Envelope`.
        case envelope
        /// A signed `MembershipEvent`.
        case roster
        /// A wrapped group key, a `KeyGrant`.
        case grant
    }

    public var kind: Kind
    public var id: String
    public var body: Data

    public init(kind: Kind, id: String, body: Data) {
        self.kind = kind
        self.id = id
        self.body = body
    }
}

/// Where a transport stopped reading. Only the transport that gave it can read it.
public struct Cursor: Sendable, Equatable {
    public var token: Data

    public init(token: Data) { self.token = token }
}

/// The way letters reach other Macs: a shared folder today, a relay or Freenet later. It stores and forwards bytes and
/// decides nothing: who is a member, and what is genuine, are the reader's checks. Putting the same letter twice, or
/// listing a letter twice, is harmless.
public protocol Transport: Sendable {
    func put(_ letter: Letter) throws
    /// Every letter that arrived after `cursor` (all of them when nil), and the cursor to pass next time.
    func list(after cursor: Cursor?) throws -> (letters: [Letter], cursor: Cursor)
}

/// A folder the team syncs (iCloud Drive, Syncthing): one file per letter, `<kind>/<id>-<digest>.json`. The digest in
/// the name means a planted file cannot take the place of a real one. Reading never trusts a name.
public struct FolderTransport: Transport {
    public static let subfolder = "sync"
    private let root: URL

    public init(team: URL) { root = team.appending(path: Self.subfolder) }

    public func put(_ letter: Letter) throws {
        let folder = root.appending(path: letter.kind.rawValue)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: letter.body).prefix(4).map { String(format: "%02x", $0) }.joined()
        let name = "\(TeamFolder.safe(letter.id))-\(digest).json"
        try letter.body.write(to: folder.appending(path: name), options: .atomic)
    }

    public func list(after cursor: Cursor?) throws -> (letters: [Letter], cursor: Cursor) {
        let seen = Set(cursor.flatMap { try? JSONDecoder().decode([String].self, from: $0.token) } ?? [])
        var found: [(name: String, letter: Letter)] = []
        for kind in Letter.Kind.allCases {
            let folder = root.appending(path: kind.rawValue)
            let files =
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                let name = "\(kind.rawValue)/\(file.lastPathComponent)"
                guard !seen.contains(name), let body = try? Data(contentsOf: file) else { continue }
                found.append((name, Letter(kind: kind, id: file.deletingPathExtension().lastPathComponent, body: body)))
            }
        }
        let names = (seen.union(found.map(\.name))).sorted()
        return (found.map(\.letter), Cursor(token: try JSONEncoder().encode(names)))
    }
}
