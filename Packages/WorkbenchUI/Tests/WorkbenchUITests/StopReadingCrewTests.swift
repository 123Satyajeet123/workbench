import CaptureService
import Foundation
import LocalSources
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Stopping a chat is an act on the chat, not on one machine: every machine that chose it drops it, and the dialog
/// names them.
@MainActor @Suite struct StopReadingCrewTests {
    private struct Scene {
        let crew: Crew
        let store: Store
        let pip: HelperModel
        let deals: HelperModel
        let team: WhatsAppChat
        let family: WhatsAppChat
    }

    private var noon: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }

    private func chat(_ jid: String, _ name: String) throws -> WhatsAppChat {
        try JSONDecoder().decode(WhatsAppChat.self, from: Data(#"{"jid":"\#(jid)","name":"\#(name)"}"#.utf8))
    }

    /// Pip and Deals both read Team; Deals also reads Family.
    private func scene() throws -> Scene {
        let now = noon
        let store = try scratchStore(clock: { now })
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let container = try whatsApp(at: noon)
        try addGroupMember(3, chat: 2, jid: "d@s.whatsapp.net", name: "Dad", to: container)
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" }, notifier: FakeNotifier(),
            whatsAppContainer: container)
        let pip = try #require(crew.factKeepers.first)
        let dealsID = try #require(crew.create(from: .team, name: "Deals"))
        let deals = try #require(crew.helper(id: dealsID))
        let team = try chat(teamJID, "Team")
        let family = try chat(familyJID, "Family")
        let pipSource = try #require(pip.source as? WhatsAppSource)
        let dealsSource = try #require(deals.source as? WhatsAppSource)
        try pipSource.choose([team])
        try dealsSource.choose([team, family])
        return Scene(crew: crew, store: store, pip: pip, deals: deals, team: team, family: family)
    }

    private func chats(of helper: HelperModel) throws -> [String] {
        let source = try #require(helper.source as? WhatsAppSource)
        return source.chats.map(\.jid)
    }

    @Test func stoppingAChatTwoMachinesShareTakesItFromBothAndKeepsTheirOtherChats() async throws {
        let scene = try scene()
        #expect(scene.crew.otherReaders(of: scene.team, besides: scene.pip) == ["Deals"])
        #expect(
            WhatsAppSource.stopWarning(alsoStopping: ["Deals"])
                == "Workbench erases what it stored from this chat. Deals also stops reading it.")

        let dealsSource = try #require(scene.deals.source as? WhatsAppSource)
        try await dealsSource.loadMembers()
        #expect(dealsSource.members.map(\.name).sorted() == ["Asha", "Bharat", "Dad"])

        try scene.crew.stopReading(scene.team)

        #expect(dealsSource.members.map(\.name) == ["Dad"], "the people of Team go with the chat")
        #expect(try chats(of: scene.pip) == [])
        #expect(try chats(of: scene.deals) == [familyJID], "Deals loses Team and keeps Family")
        let reopened = try WhatsAppSource(
            store: scene.store, capture: try CaptureService(store: scene.store), task: scene.deals.spec.task,
            founder: { "Kabir" })
        #expect(reopened.chats.map(\.jid) == [familyJID], "the saved choice of Deals lost Team too")
        let evidence = try await dealsSource.evidence(on: WorkDay(containing: noon))
        #expect(!evidence.lines.isEmpty, "the next read of Deals does not fail, and reads Family")
        #expect(try scene.store.currentPolicy().allowList[.whatsapp] == [familyJID])
    }

    @Test func aChatOnlyOneMachineHoldsNamesNoOtherMachine() throws {
        let scene = try scene()
        #expect(scene.crew.otherReaders(of: scene.family, besides: scene.deals) == [])
        #expect(
            WhatsAppSource.stopWarning(alsoStopping: []) == WhatsAppSource.stopReadingWarning,
            "the sentence stays first and alone")
        try scene.crew.stopReading(scene.family)
        #expect(try chats(of: scene.deals) == [teamJID])
        #expect(try chats(of: scene.pip) == [teamJID], "Pip never read Family and keeps Team")
    }

    @Test func theNamesAreJoinedInPlainWords() {
        let warning = WhatsAppSource.stopWarning(alsoStopping: ["Crew", "Deals"])
        #expect(warning.hasSuffix("Crew and Deals also stop reading it."))
    }
}
