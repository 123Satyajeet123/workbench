import CryptoKit
import Foundation
import Testing

@testable import WorkbenchCore

/// A folder that cannot be trusted: copies, losses, changes, forgeries.
@Suite struct SyncHostileTests {
    private let secret = "Acme raises at a 40 crore valuation"

    private func published(_ names: [String] = ["Kabir", "Asha", "Dev"]) throws -> Cluster {
        let team = try Cluster.formed(names)
        try team.sync(team.founder).publish([
            .event(workEvent("e1", by: "Kabir", clock: 1, text: secret)),
            .event(workEvent("e2", by: "Kabir", clock: 2, text: "two")),
            .event(workEvent("e3", by: "Kabir", clock: 3, text: "three")),
        ])
        try team.spreadFully()
        return team
    }

    private func envelopeFiles(_ replica: Replica) -> [URL] {
        replica.files.filter { $0.path.contains("/envelope/") }.sorted { $0.path < $1.path }
    }

    private func ids(_ replica: Replica, in team: Cluster) throws -> [String] {
        try team.sync(replica).receive().events.map(\.id)
    }

    @Test(arguments: [1, 2, 3] as [UInt64]) func fiveReplicasConvergeThroughRandomOrderDuplicatesAndDelays(
        seed: UInt64
    ) throws {
        let team = try Cluster.formed(["Kabir", "Asha", "Dev", "Esha", "Farid"])
        var random = SeededRandom(seed)
        var all: Set<String> = []
        for round in 0..<4 {
            for (index, replica) in team.replicas.enumerated() {
                let event = workEvent(
                    "\(replica.name)-\(round)", by: replica.name, clock: round * 10 + index + 1, text: "n\(round)")
                try team.sync(replica).publish([.event(event)])
                all.insert(event.id)
            }
            try team.gossip(using: &random)
            for replica in team.replicas { #expect(Set(try ids(replica, in: team)).isSubset(of: all)) }
        }
        try team.spreadFully()
        let expected = try ids(team.founder, in: team)
        #expect(Set(expected) == all && expected.count == all.count)
        for replica in team.replicas { #expect(try ids(replica, in: team) == expected, "\(replica.name) differs") }
        let clocks = try team.sync(team.founder).receive().events.map(\.clock)
        #expect(clocks == clocks.sorted(), "Lamport order")
    }

    @Test func aForgedAuthorFieldIsRefused() throws {
        let team = try published()
        let mallory = team.replica("Dev")
        let key = SymmetricKey(size: .bits256)
        var forged = try Envelope(
            sealing: Data("{}".utf8), sequence: 9, lamport: 9, group: "x.y", key: key, author: mallory.keys)
        forged.author = team.founder.keys.card.fingerprint
        forged.id = Envelope.id(author: forged.author, sequence: 9)
        try team.founder.transport.put(try TeamSync.letter(.envelope, forged.id, forged))
        let seen = try team.sync(team.replica("Asha")).receive()
        let kabirs = try team.sync(team.founder).receive()
        #expect(kabirs.unverified == 1 && kabirs.events.count == 3)
        #expect(seen.unverified == 0, "Asha's folder never got it")
    }

    @Test func aChangedCiphertextIsRefusedAndTheRestStillReads() throws {
        let team = try published()
        let asha = team.replica("Asha")
        let file = try #require(envelopeFiles(asha).first)
        var envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
        envelope.ciphertext[0] ^= 0xFF
        try TeamSync.letter(.envelope, envelope.id, envelope).body.write(to: file)
        let seen = try team.sync(asha).receive()
        #expect(seen.unverified == 1 && seen.events.count == 2)
    }

    @Test func aReplayedEnvelopeCountsOnceAndAReplayWithAChangedFieldIsRefused() throws {
        let team = try published()
        let asha = team.replica("Asha")
        let file = try #require(envelopeFiles(asha).first)
        let original = try Data(contentsOf: file)
        try original.write(to: file.deletingLastPathComponent().appending(path: "replay.json"))
        var seen = try team.sync(asha).receive()
        #expect(seen.events.count == 3 && seen.unverified == 0, "a plain copy is harmless")

        var moved = try JSONDecoder().decode(Envelope.self, from: original)
        moved.lamport = 99
        try TeamSync.letter(.envelope, moved.id, moved).body.write(
            to: file.deletingLastPathComponent().appending(path: "replay2.json"))
        seen = try team.sync(asha).receive()
        #expect(seen.events.map(\.id) == ["e1", "e2", "e3"] && seen.unverified == 1)
    }

    @Test func anEnvelopeFromAnotherTeamsFounderIsNotAccepted() throws {
        let team = try published()
        let other = try Cluster.formed(["Rival", "Spy"])
        try other.sync(other.founder).publish([.event(workEvent("x", by: "Rival", clock: 1))])
        try team.copy(other.founder.files, from: other.founder, to: team.founder)
        let seen = try team.sync(team.founder).receive()
        #expect(seen.events.count == 3 && seen.unverified > 0)
    }

    @Test func aDroppedEnvelopeShowsAsAGapAndReorderingChangesNothing() throws {
        let team = try published()
        let asha = team.replica("Asha")
        let files = envelopeFiles(asha)
        let before = try ids(asha, in: team)
        for (index, file) in files.enumerated() {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(1_000 - index))], ofItemAtPath: file.path)
        }
        #expect(try ids(asha, in: team) == before, "file order does not matter")

        let middle = try #require(
            files.first { try! JSONDecoder().decode(Envelope.self, from: Data(contentsOf: $0)).sequence == 2 })
        try FileManager.default.removeItem(at: middle)
        let seen = try team.sync(asha).receive()
        #expect(seen.events.map(\.id) == ["e1", "e3"] && seen.gaps == ["Kabir": [2]])
    }

    @Test func aFakeMemberEventAddsNoOneAndTheirEnvelopesAreRefused() throws {
        let team = try published()
        let mallory = Replica(name: "Mallory")
        let fake = try MembershipEvent(
            kind: .admit, subject: "Mallory", card: mallory.keys.card, lamport: 50, signedBy: mallory.keys)
        let asha = team.replica("Asha")
        try asha.transport.put(try TeamSync.letter(.roster, fake.id, fake))
        let key = SymmetricKey(size: .bits256)
        let envelope = try Envelope(
            sealing: Data("{}".utf8), sequence: 1, lamport: 60, group: "x.y", key: key, author: mallory.keys)
        try asha.transport.put(try TeamSync.letter(.envelope, envelope.id, envelope))
        let seen = try team.sync(asha).receive()
        #expect(seen.roster.members.map(\.name) == ["Asha", "Dev", "Kabir"])
        #expect(seen.unverified == 2 && seen.events.count == 3)
    }

    @Test func aDumpOfTheFolderShowsNoPlaintext() throws {
        let team = try published()
        let dump = try team.replicas.flatMap(\.files).reduce(into: Data()) { $0.append(try Data(contentsOf: $1)) }
        for word in [secret, "valuation", "crore", "deal-1", "Acme"] {
            #expect(dump.range(of: Data(word.utf8)) == nil, "\(word) is in the dump")
        }

        let plain = Data(try Coding.json(workEvent("e1", by: "Kabir", clock: 1, text: secret)).utf8)
        #expect(plain.range(of: Data(secret.utf8)) != nil, "the check can tell: a plain event shows it")
    }
}
