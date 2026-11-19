import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct AudienceTests {
    private let asha = Team.Person(id: 2, name: "Asha", role: "Analyst")
    private let kabir = Team.Person(id: 3, name: "Kabir", role: "Partner")

    @Test func aShareGoesOnlyWhenEveryRecipientCanAlreadyReadTheSource() {
        #expect(Audience.missing(recipients: [asha, kabir], readers: [2, 3]).isEmpty)
        #expect(Audience.missing(recipients: [asha, kabir], readers: [2]) == [kabir])
    }

    @Test func anUnknownAudienceOrAnUnsavedPersonIsRefused() {
        #expect(Audience.missing(recipients: [asha, kabir], readers: nil) == [asha, kabir])
        let unsaved = Team.Person(name: "New", role: "")
        #expect(Audience.missing(recipients: [unsaved], readers: [2, 3]) == [unsaved])
    }

    @Test func aTeammateReadsAGroupOnlyWhileTheirLinkedIdIsInIt() {
        let links: [Int64: String] = [2: "91111@s.whatsapp.net", 3: "92222@s.whatsapp.net"]
        #expect(Audience.readers(links: links, group: ["91111@s.whatsapp.net", "92222@s.whatsapp.net"]) == [2, 3])
        #expect(Audience.readers(links: links, group: ["91111@s.whatsapp.net"]) == [2])
        #expect(Audience.readers(links: [:], group: ["91111@s.whatsapp.net"]).isEmpty)
    }

    @Test func theLatestLinkWinsAndEveryActIsLogged() throws {
        let store = try makeStore()
        try store.saveTeam(
            Team(
                name: "Brave",
                people: [.init(name: "Jeet", role: "Founder", isMe: true), .init(name: "Asha", role: "")]))
        let person = try #require(try store.queries.team()?.people.first { !$0.isMe })
        try store.link(person, whatsapp: "old@s.whatsapp.net")
        try store.link(person, whatsapp: "new@s.whatsapp.net")
        #expect(try store.queries.whatsappLinks() == [try #require(person.id): "new@s.whatsapp.net"])
        try store.log("share_day", target: "team.ledger", detail: ["day": "2026-09-21"])
        #expect(try store.queries.actions().map(\.detail) == [["day": "2026-09-21"]])
    }

    @Test func aSharedDayCarriesNoRejectedItemAndShowsOnlyToItsAudience() throws {
        let today = WorkDay(containing: t0)
        let item = { (quote: String, state: Mark) in
            var item = Item(
                task: "team.ledger", day: today, scope: "", source: .whatsapp, citeFirst: 1, citeLast: 1, start: t0,
                end: t0, fields: ["person": "Asha", "kind": "plan", "text": quote], quote: quote, run: 1)
            item.state = state
            return item
        }
        let machine = Machine(id: 1, name: "Pip", template: "team.ledger", spec: .team, state: .active)
        let shared = SharedDay(
            author: "Jeet", machine: machine, day: today,
            items: [item("ship deck", .confirmed), item("wrong", .rejected), item("call LP", .proposed)],
            audience: ["Jeet", "Asha"], at: t0)
        #expect(shared.entries.map(\.quote) == ["ship deck", "call LP"])
        #expect(shared.isVisible(to: "Asha") && !shared.isVisible(to: "Kabir"))
        let folder = temporaryDirectory()
        try shared.write(to: folder)
        #expect(SharedDay.read(from: folder).files == [shared])
        #expect(SharedMachine.read(from: folder).files.isEmpty)
        try SharedDay.remove(author: "Jeet", parts: shared.fileParts, from: folder)
        #expect(SharedDay.read(from: folder).files.isEmpty)
    }
}
