import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct TodayModelTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private struct Setup {
        let store: Store
        let crew: Crew
        let model: TodayModel
        let clock: TestClock

        var pip: HelperModel { crew.machines.first { $0.spec.task == HelperSpec.team.task }! }
        var today: WorkDay { WorkDay(containing: clock.now) }
        func fact(_ id: Int64) throws -> Item {
            try #require(store.queries.items(of: HelperSpec.team.task, on: today).first { $0.id == id })
        }
    }

    private func setup(sample: Bool = true) async throws -> Setup {
        let clock = TestClock(noon)
        let store = try scratchStore(clock: { clock.now })
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" }, notifier: FakeNotifier())
        if sample { try await TodaySample.populate(store: store, crew: crew) }
        return Setup(store: store, crew: crew, model: TodayModel(store: store, crew: crew), clock: clock)
    }

    @Test func needsYouHoldsTheActFindingThenAsksThenOverdueThenDueToday() async throws {
        let day = try await setup()
        let today = day.today
        #expect(day.model.needs.map(\.id) == [8, 2, 3, 6, 1])
        #expect(
            day.model.needs.map(\.reason) == [.act, .asks, .asks, .due(today.adding(days: -1)), .due(today)])
    }

    @Test func teamAndProjectsHaveOneLinePerScopeAndProjectsCountTheirOpenFacts() async throws {
        let day = try await setup()
        #expect(day.model.team.map(\.subject) == ["Asha", "Meera", "Raj"])
        #expect(day.model.projects.map(\.subject) == ["Hiring", "Login", "Payments"])
        #expect(day.model.projects.map(\.openCount) == [2, 2, 1])
        #expect(day.model.team[0].facts.compactMap(\.id) == [1, 2, 7])
    }

    @Test func aDayWithNothingShowsNothingAndSaysSo() async throws {
        let day = try await setup(sample: false)
        #expect(day.model.isEmpty && day.model.team.isEmpty && day.model.projects.isEmpty)
        #expect(day.model.people.isEmpty && day.model.projectGroups.isEmpty)
    }

    @Test func todayFollowsAReadingThroughTheCrewsSignalThatItemsChanged() async throws {
        let day = try await setup(sample: false)
        try await TodaySample.populate(store: day.store, crew: day.crew)
        #expect(day.model.isEmpty, "nothing tells Today yet")
        day.pip.itemsChanged()
        #expect(!day.model.isEmpty && day.model.needs.count == 5)
    }

    @Test func doneClosesABlockerAsResolvedAndItLeavesNeedsYouButStaysInItsGroup() async throws {
        let day = try await setup()
        day.model.perform(.done, on: [try day.fact(2)], text: "Done")
        #expect(try day.fact(2).closed?.outcome == "resolved")
        #expect(!day.model.needs.contains { $0.id == 2 })
        let asha = try #require(day.model.people.first { $0.name == "Asha" })
        #expect(!asha.open.contains { $0.id == 2 } && asha.rest.contains { $0.id == 2 })
    }

    @Test func undoReopensWhatDoneClosed() async throws {
        let day = try await setup()
        day.model.perform(.done, on: [try day.fact(3)], text: "Done")
        #expect(!day.model.needs.contains { $0.id == 3 } && day.model.undoable != nil)
        day.model.undo()
        #expect(day.model.needs.contains { $0.id == 3 } && day.model.undoable == nil)
        #expect(try day.fact(3).closed == nil)
    }

    @Test func doneOnAFindingClosesItAsHandled() async throws {
        let day = try await setup()
        let finding = try #require(day.model.needs.first { $0.id == 8 }).item
        day.model.perform(.done, on: [finding], text: "Done")
        #expect(!day.model.needs.contains { $0.id == 8 })
        #expect(
            try day.store.queries.items(of: finding.task, on: day.today).first?.closed?.outcome == "handled")
    }

    @Test func notRelevantOnASummaryLineHidesItsFactsAndTheLineLeaves() async throws {
        let day = try await setup()
        let line = try #require(day.model.team.first { $0.subject == "Meera" })
        day.model.perform(.notRelevant, on: line.facts, text: "Hidden")
        #expect(!day.model.team.contains { $0.subject == "Meera" })
        #expect(!day.model.people.contains { $0.name == "Meera" })
        #expect(!day.model.projects.contains { $0.subject == "Hiring" })
        #expect(!day.model.needs.contains { $0.id == 6 })
    }

    @Test func aHiddenFactStaysOnItsMachinesPageShownAsHidden() async throws {
        let day = try await setup()
        day.model.perform(.notRelevant, on: [try day.fact(5)], text: "Hidden")
        let shown = try #require(day.pip.open.first { $0.id == 5 })
        #expect(shown.hiding == .hidden && shown.state == .confirmed)
    }

    @Test func wrongHidesTheFactAndMarksItRejected() async throws {
        let day = try await setup()
        day.model.perform(.wrong, on: [try day.fact(3)], text: "Hidden")
        #expect(try day.fact(3).state == .rejected)
        #expect(!day.model.needs.contains { $0.id == 3 })
        #expect(!(day.model.people.first { $0.name == "Raj" }?.open.contains { $0.id == 3 } ?? false))
    }

    @Test func aSnoozedFactIsGoneUntilItsDayThenReturns() async throws {
        let day = try await setup()
        let until = day.today.adding(days: 2)
        day.model.perform(.snooze(until: until), on: [try day.fact(2)], text: "Snoozed")
        #expect(!day.model.needs.contains { $0.id == 2 })
        day.clock.set(until.start.addingTimeInterval(-60))
        day.model.refresh()
        #expect(!day.model.needs.contains { $0.id == 2 })
        day.clock.set(until.start)
        day.model.refresh()
        #expect(day.model.needs.contains { $0.id == 2 })
    }

    @Test func undoingAnActionOnASummaryLineBringsTheLineBack() async throws {
        let day = try await setup()
        let line = try #require(day.model.team.first { $0.subject == "Raj" })
        day.model.perform(.wrong, on: line.facts, text: "Hidden")
        #expect(!day.model.team.contains { $0.subject == "Raj" })
        day.model.undo()
        #expect(day.model.team.contains { $0.subject == "Raj" })
    }

    @Test func aFactOlderThanAWeekStaysWhileOpenAndLeavesTheWindowWhenDone() async throws {
        let day = try await setup()
        let weekLater = day.today.adding(days: 9)
        day.clock.set(weekLater.start.addingTimeInterval(3600))
        day.model.refresh()
        #expect(day.model.people.first { $0.name == "Asha" }?.open.map(\.id) == [1, 2])
        #expect(day.model.people.first { $0.name == "Raj" }?.rest.isEmpty == true)
    }

    @Test func aLineAroundACitedMessageIncludesItsNeighboursAndNothingFarther() {
        let item = Item(
            task: "t", day: WorkDay(containing: noon), scope: "", source: .whatsapp, citeFirst: 11, citeLast: 11,
            start: noon, end: noon, fields: [:], quote: "q", run: RunID(1))
        let lines = (8...15).map { Evidence(id: Int64($0), start: noon, line: "line \($0)", quotable: []) }
        let window = ChatLine.around(item, in: lines, reach: 2)
        #expect(window.map(\.id) == [9, 10, 11, 12, 13])
        #expect(window.filter(\.isCited).map(\.id) == [11])
    }
}
