import CaptureService
import Foundation
import Testing
import WorkbenchCore

/// Taking a chat off the allow-list withdraws the consent for it: its lines and their copies go, no other chat's.
@MainActor @Suite struct WhatsAppWithdrawalTests {
    typealias Rig = WhatsAppEvidenceTests.Rig

    private func word(_ name: String) -> String { "zxq\(UInt32.random(in: 100_000...999_999))\(name)" }

    private func rigWithTwoReadChats(team: String, family: String) async throws -> (Rig, CaptureService) {
        let rig = try Rig(allowing: [groupJID, otherGroupJID])
        try rig.fixture.message(chat: 4, type: 0, text: team, member: 1, pk: 11)
        try rig.fixture.message(chat: 5, type: 0, text: family, member: 4, pk: 12)
        try await rig.ingest([groupJID, otherGroupJID])
        let service = try CaptureService(store: rig.store, owner: .success(WhatsAppEvidenceTests.owner))
        return (rig, service)
    }

    @Test func removingAChatErasesItsLinesAndNoOtherChats() async throws {
        let (team, family) = (word("team"), word("family"))
        let (rig, service) = try await rigWithTwoReadChats(team: team, family: family)
        #expect(try rig.copies(of: team) > 0 && rig.copies(of: family) > 0)
        try service.update { $0.allowList[.whatsapp]?.remove(groupJID) }
        #expect(try rig.copies(of: team) == 0, "the removed chat is gone from the file and its log")
        #expect(try rig.copies(of: family) > 0, "the other chat stays")
        #expect(try rig.texts() == [family])
    }

    @Test func addingAChatOrChangingAnotherSettingErasesNothing() async throws {
        let (team, family) = (word("team"), word("family"))
        let (rig, service) = try await rigWithTwoReadChats(team: team, family: family)
        try service.update { $0.allowList[.whatsapp]?.insert(otherJID) }
        try service.update { $0.switches[.screen] = true }
        #expect(try rig.copies(of: team) > 0 && rig.copies(of: family) > 0)
    }
}
