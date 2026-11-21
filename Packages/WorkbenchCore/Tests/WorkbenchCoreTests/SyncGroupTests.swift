import Foundation
import Testing

@testable import WorkbenchCore

/// Who can read what: the audience rule as a key rule.
@Suite struct SyncGroupTests {
    private let secret = "Acme raises at a 40 crore valuation"

    @Test func aMemberOfTheAudienceReadsAndAMemberOutsideItCannot() throws {
        let team = try Cluster.formed(["Kabir", "Asha", "Dev"])
        let kabir = team.sync(team.founder)
        try kabir.publish([.event(workEvent("e1", by: "Kabir", clock: 1, text: secret, audience: ["Kabir", "Asha"]))])
        try team.spreadFully()

        let asha = try team.sync(team.replica("Asha")).receive()
        #expect(asha.events.map(\.id) == ["e1"] && asha.events.first?.item?.quote == secret)
        let dev = try team.sync(team.replica("Dev")).receive()
        #expect(
            dev.events.isEmpty && dev.undecryptable == 1 && dev.unverified == 0, "Dev is on the team, not in the group")
    }

    @Test func aTeamWideThingGoesToEveryMemberAndAPersonNeverAdmittedReadsNothing() throws {
        let team = try Cluster.formed(["Kabir", "Asha"])
        try team.sync(team.founder).publish([.event(workEvent("e1", by: "Kabir", clock: 1, text: "hello"))])
        let outsider = Replica(name: "Mallory")
        try team.copy(team.founder.files, from: team.founder, to: outsider)
        let seen = try TeamSync(
            transport: outsider.transport, keys: outsider.keys, name: "Mallory", founder: team.founder.member
        ).receive()
        #expect(seen.events.isEmpty && seen.undecryptable == 1)
        try team.spreadFully()
        #expect(try team.sync(team.replica("Asha")).receive().events.map(\.id) == ["e1"])
    }

    @Test func aMemberRemovedMidStreamKeepsTheOldEventsAndCannotReadTheNewOnes() throws {
        let team = try Cluster.formed(["Kabir", "Asha", "Dev"])
        let kabir = team.sync(team.founder)
        try kabir.publish([.event(workEvent("old", by: "Kabir", clock: 1, text: "before"))])
        try team.spreadFully()
        let devSync = team.sync(team.replica("Dev"))
        let before = try devSync.receive()
        #expect(before.events.map(\.id) == ["old"])

        try kabir.remove(team.replica("Dev").member)
        try kabir.publish([.event(workEvent("new", by: "Kabir", clock: 2, text: "after"))])
        try team.spreadFully()

        let afterDev = try devSync.receive()
        #expect(afterDev.events.map(\.id) == ["old"], "Dev still opens what came before, and not what came after")
        #expect(afterDev.undecryptable == 1)
        #expect(try team.sync(team.replica("Asha")).receive().events.map(\.id) == ["old", "new"])
    }

    @Test func aChangedSetGetsANewKeyAndAnUnchangedSetKeepsItsKey() throws {
        let team = try Cluster.formed(["Kabir", "Asha"])
        let kabir = team.sync(team.founder)
        try kabir.publish([.event(workEvent("e1", by: "Kabir", clock: 1))])
        try kabir.publish([.event(workEvent("e2", by: "Kabir", clock: 2))])
        let groups = try envelopes(in: team.founder).map(\.group)
        #expect(groups.count == 2 && Set(groups).count == 1, "one key for one set")

        let dev = Replica(name: "Dev")
        try TeamSync.announce(name: "Dev", keys: dev.keys, on: dev.transport)
        try team.copy(dev.files, from: dev, to: team.founder)
        try kabir.admit(
            try #require(try TeamSync.announcements(on: team.founder.transport).first { $0.subject == "Dev" }))
        try kabir.publish([.event(workEvent("e3", by: "Kabir", clock: 3))])
        #expect(Set(try envelopes(in: team.founder).map(\.group)).count == 2, "a new member means a new key")
    }

    @Test func aThingForSomeoneWithNoConfirmedKeyStaysOnThisMac() throws {
        let team = try Cluster.formed(["Kabir", "Asha"])
        let outcome = try team.sync(team.founder).publish([
            .event(workEvent("e1", by: "Kabir", clock: 1, text: "x", audience: ["Kabir", "Nobody"])),
            .event(workEvent("e2", by: "Kabir", clock: 2, text: "y")),
        ])
        #expect(outcome == .init(sent: 1, held: 1))
        #expect(try team.sync(team.founder).receive().events.map(\.id) == ["e2"])
    }

    @Test func sendingTheSameThingTwiceSendsOnce() throws {
        let team = try Cluster.formed(["Kabir", "Asha"])
        let thing = SharedThing.event(workEvent("e1", by: "Kabir", clock: 1))
        let kabir = team.sync(team.founder)
        #expect(try kabir.publish([thing]).sent == 1 && (try kabir.publish([thing])).sent == 0)
    }

    @Test func aPersonOnlyWritesInTheirOwnNameAndAWithdrawnDayDisappears() throws {
        let team = try Cluster.formed(["Kabir", "Asha"])
        let asha = team.sync(team.replica("Asha"))
        let forged = SharedThing.event(workEvent("e1", by: "Kabir", clock: 1, text: "Kabir says so"))
        try asha.publish([forged])
        try team.spreadFully()
        let seen = try team.sync(team.founder).receive()
        #expect(seen.events.isEmpty && seen.unverified == 1, "Asha signed a thing that says Kabir wrote it")

        let machine = Machine(id: 1, name: "Pip", template: "team.ledger", spec: .team, state: .active)
        let day = SharedDay(
            author: "Asha", machine: machine, day: WorkDay(containing: t0), items: [], audience: ["Asha", "Kabir"],
            at: t0)
        try asha.publish([.day(day)])
        #expect(try asha.receive().days.map(\.id) == [day.id])
        try asha.publish([.retraction(key: SharedDay.key(author: "Asha", task: day.task, day: day.day), by: "Asha")])
        #expect(try asha.receive().days.isEmpty)
    }

    private func envelopes(in replica: Replica) throws -> [Envelope] {
        try replica.transport.list(after: nil).letters.filter { $0.kind == .envelope }.map {
            try JSONDecoder().decode(Envelope.self, from: $0.body)
        }
    }
}
