import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct StateKeyTests {
    private struct Saved: Codable, Equatable {
        var name: String
        var hours: [Int]
    }

    @Test func aJSONKeyReadsBackWhatWasSavedAndAMissingKeyIsNil() throws {
        let store = try scratchStore()
        let key = StateKey<Saved>.json("saved")
        #expect(try key.load(from: store) == nil)
        let value = Saved(name: "Pip", hours: [9, 15])
        try key.save(value, to: store)
        #expect(try key.load(from: store) == value)
    }

    @Test func aJSONKeyWritesTheSameTextAsPlainJSONEncoding() throws {
        let store = try scratchStore()
        try MachineKey.sites("scout").save(["acme.com", "mail.google.com"], to: store)
        #expect(try store.queries.state(forKey: "scout.sites") == #"["acme.com","mail.google.com"]"#)
    }

    @Test func aClearedKeyReadsAsNilAndKeepsEmptyText() throws {
        let store = try scratchStore()
        let key = StateKey<Saved>.json("saved")
        try key.save(Saved(name: "Pip", hours: []), to: store)
        try key.clear(in: store)
        #expect(try key.load(from: store) == nil)
        #expect(try store.queries.state(forKey: "saved") == "")
    }

    @Test func textAndMomentAndDayAndSwitchKeysRoundTrip() throws {
        let store = try scratchStore()
        let moment = Date(timeIntervalSince1970: 1_790_000_000)
        let day = WorkDay(containing: moment)
        try StateKey<Int64>.text("line").save(42, to: store)
        try StateKey<Date>.moment("when").save(moment, to: store)
        try StateKey<WorkDay>.day("day").save(day, to: store)
        try StateKey<Bool>.onOff("on").save(true, to: store)
        #expect(try store.queries.state(forKey: "line") == "42")
        #expect(try StateKey<Int64>.text("line").load(from: store) == 42)
        #expect(try StateKey<Date>.moment("when").load(from: store) == moment)
        #expect(try StateKey<WorkDay>.day("day").load(from: store) == day)
        #expect(try store.queries.state(forKey: "on") == "on")
        #expect(try StateKey<Bool>.onOff("on").load(from: store) == true)
        #expect(try StateKey<Int64>.text("absent").load(from: store) == nil)
    }

    @Test func machineKeysKeepTheNamesFoundersStoresAlreadyHold() throws {
        let day = try #require(WorkDay("2026-11-20"))
        #expect(MachineKey.nudge("team").name == "team.nudge")
        #expect(MachineKey.nudged("team").name == "team.nudged")
        #expect(MachineKey.watch("team").name == "team.watch")
        #expect(MachineKey.watched("team").name == "team.watched")
        #expect(MachineKey.lastLine("team", scope: "g@g.us", day: day).name == "team.read.g@g.us.2026-11-20")
        #expect(MachineKey.trial("team").name == "team.trial")
        #expect(MachineKey.sites("scout").name == "scout.sites")
        #expect(MachineKey.chats("team").name == "team.chats")
        #expect(MachineKey.members("team").name == "team.members")
        #expect(MachineKey.drift("team").name == "team.drift")
    }
}
