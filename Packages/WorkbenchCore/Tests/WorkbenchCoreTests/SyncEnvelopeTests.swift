import CryptoKit
import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct SyncEnvelopeTests {
    private let author = PersonKeys()
    private let key = SymmetricKey(size: .bits256)

    private func sealed(_ text: String = "secret", lamport: Int = 7) throws -> Envelope {
        try Envelope(
            sealing: Data(text.utf8), sequence: 1, lamport: lamport, group: "g.1", key: key, author: author)
    }

    @Test func keysComeBackFromTheirRawFormAndTheFingerprintIsTwentyHexDigits() throws {
        let again = try PersonKeys(raw: author.raw)
        #expect(again.card == author.card)
        #expect(author.card.fingerprint.count == 20 && author.card.spoken.split(separator: " ").count == 5)
        #expect(PersonKeys().card.fingerprint != author.card.fingerprint)
        #expect(throws: SyncError.badKeys) { try PersonKeys(raw: Data(count: 10)) }
    }

    @Test func aSealedEnvelopeOpensWithItsKeyAndItsAuthorsCardOnly() throws {
        let envelope = try sealed()
        #expect(envelope.isSigned(by: author.card))
        #expect(try envelope.open(with: key) == Data("secret".utf8))
        #expect(!envelope.isSigned(by: PersonKeys().card), "another person's card does not verify it")
        #expect(throws: (any Error).self) { try envelope.open(with: SymmetricKey(size: .bits256)) }
    }

    @Test func changingAnyFieldBreaksTheSignature() throws {
        let envelope = try sealed()
        var changes: [Envelope] = []
        var other = envelope
        other.lamport += 1
        changes.append(other)
        other = envelope
        other.group = "g.2"
        changes.append(other)
        other = envelope
        other.id = Envelope.id(author: envelope.author, sequence: 2)
        changes.append(other)
        other = envelope
        other.ciphertext[0] ^= 1
        changes.append(other)
        other = envelope
        other.nonce[0] ^= 1
        changes.append(other)
        other = envelope
        other.author = PersonKeys().card.fingerprint
        changes.append(other)
        for changed in changes { #expect(!changed.isSigned(by: author.card)) }
    }

    @Test func theCipherAlsoBindsIdAndGroupSoAResignedHeaderStillDoesNotOpen() throws {
        let envelope = try sealed()
        var moved = envelope
        moved.group = "g.2"
        #expect(throws: (any Error).self) { try moved.open(with: key) }
    }

    @Test func theSequenceComesFromTheIdAndMustMatchTheAuthor() throws {
        var envelope = try sealed()
        #expect(envelope.sequence == 1)
        envelope.id = "someone-else.1"
        #expect(envelope.sequence == nil && !envelope.isSigned(by: author.card))
    }

    @Test func aGroupKeyOpensOnlyForARecipientWhoseGrantTheSenderSigned() throws {
        let asha = PersonKeys()
        let dev = PersonKeys()
        let members = [author.card, asha.card]
        let group = GroupKey.newName(for: members)
        let grants = try KeyGrant.grants(for: key, group: group, members: members, from: author)
        let forAsha = try #require(grants.first { $0.recipient == asha.card.fingerprint })
        #expect(
            try forAsha.open(from: author.card, with: asha).withUnsafeBytes { Data($0) }
                == key.withUnsafeBytes { Data($0) })
        #expect(throws: (any Error).self) { try forAsha.open(from: author.card, with: dev) }
        #expect(throws: (any Error).self) { try forAsha.open(from: dev.card, with: asha) }
        var widened = forAsha
        widened.members.append(dev.card.fingerprint)
        #expect(throws: (any Error).self) { try widened.open(from: author.card, with: asha) }
    }

    @Test func aHelloAloneAddsNoOneAndOnlyTheFoundersSignedAdmitDoes() throws {
        let founder = PersonKeys()
        let asha = PersonKeys()
        let mallory = PersonKeys()
        let root = Roster.Member(name: "Kabir", card: founder.card)
        let hello = try MembershipEvent(kind: .hello, subject: "Asha", card: asha.card, lamport: 1, signedBy: asha)
        var roster = Roster([hello], founder: root)
        #expect(roster.members == [root] && roster.waiting.map(\.subject) == ["Asha"])

        let admit = try MembershipEvent(kind: .admit, subject: "Asha", card: asha.card, lamport: 2, signedBy: founder)
        roster = Roster([hello, admit], founder: root)
        #expect(roster.members.map(\.name) == ["Asha", "Kabir"] && roster.waiting.isEmpty && roster.rejected == 0)

        let fake = try MembershipEvent(
            kind: .admit, subject: "Mallory", card: mallory.card, lamport: 3, signedBy: mallory)
        roster = Roster([hello, admit, fake], founder: root)
        #expect(roster.members.map(\.name) == ["Asha", "Kabir"] && roster.rejected == 1)
    }

    @Test func aRemovalEndsMembershipAndAReplayedAdmitDoesNotBringThePersonBack() throws {
        let founder = PersonKeys()
        let asha = PersonKeys()
        let root = Roster.Member(name: "Kabir", card: founder.card)
        let admit = try MembershipEvent(kind: .admit, subject: "Asha", card: asha.card, lamport: 2, signedBy: founder)
        let remove = try MembershipEvent(kind: .remove, subject: "Asha", card: asha.card, lamport: 5, signedBy: founder)
        #expect(Roster([admit, remove], founder: root).members == [root])
        #expect(Roster([remove, admit, admit], founder: root).members == [root], "order and copies change nothing")
        let again = try MembershipEvent(kind: .admit, subject: "Asha", card: asha.card, lamport: 9, signedBy: founder)
        #expect(Roster([admit, remove, again], founder: root).members.count == 2, "a new admit does")
        let removeFounder = try MembershipEvent(
            kind: .remove, subject: "Kabir", card: founder.card, lamport: 6, signedBy: founder)
        #expect(Roster([removeFounder], founder: root).members == [root])
    }
}
