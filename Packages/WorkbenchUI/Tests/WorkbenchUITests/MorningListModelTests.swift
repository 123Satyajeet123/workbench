import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Today's morning list over TodaySample's day, for a founder who is Asha, owner of facts 1 and 2.
@Suite struct MorningListModelTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private struct Setup {
        let store: Store
        let model: TodayModel
        let clock: TestClock
        let day: WorkDay

        func fact(_ id: Int64) throws -> Item {
            try #require(store.queries.items(of: HelperSpec.team.task, on: day).first { $0.id == id })
        }

        func ids(_ kind: MorningSection.Kind) -> [Int64] {
            model.sections.first { $0.kind == kind }?.lines.compactMap(\.id) ?? []
        }
    }

    private func setup(me: String = "Asha") async throws -> Setup {
        let clock = TestClock(noon)
        let store = try scratchStore(clock: { clock.now })
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { me }, notifier: FakeNotifier())
        try await TodaySample.populate(store: store, crew: crew)
        return Setup(
            store: store, model: TodayModel(store: store, crew: crew, me: { me }), clock: clock,
            day: WorkDay(containing: noon))
    }

    @Test func theFoundersOwnFactsAreWhatIOweAndAnotherPersonsAreWaitedOn() async throws {
        let day = try await setup()
        #expect(day.ids(.owe) == [1, 2, 3], "Asha's two facts, and the question that asks the founder")
        #expect(day.ids(.slipped) == [6] && day.ids(.waitingOn) == [5])
    }

    @Test func handingAFactToAnotherPersonMovesItToWaitingOnThemAndUndoTakesItBack() async throws {
        let day = try await setup()
        day.model.perform(.handOff(to: "Meera"), on: [try day.fact(1)], text: "Handed")
        #expect(!day.ids(.owe).contains(1))
        let waiting = try #require(day.model.sections.first { $0.kind == .waitingOn })
        #expect(waiting.owners.first { $0.owner == "Meera" }?.needs.compactMap(\.id) == [1, 5])
        #expect(try day.fact(1).handedTo == "Meera")
        day.model.undo()
        #expect(day.ids(.owe).contains(1))
        #expect(try day.fact(1).handedTo == nil)
    }

    @Test func aHandOffToNoOneNamedWritesNothing() async throws {
        let day = try await setup()
        day.model.perform(.handOff(to: "  "), on: [try day.fact(1)], text: "Handed")
        #expect(try day.fact(1).handedTo == nil && day.model.undoable == nil)
    }

    @Test func theMarksOnTodayAreLifecycleEventsAndTheExistingMarks() async throws {
        let day = try await setup()
        day.model.perform(.done, on: [try day.fact(2)], text: "Done")
        day.model.perform(.snooze(until: day.day.adding(days: 2)), on: [try day.fact(3)], text: "Snoozed")
        day.model.perform(.wrong, on: [try day.fact(6)], text: "Wrong")
        day.model.perform(.notRelevant, on: [try day.fact(5)], text: "Hidden")
        #expect(try day.fact(2).closed?.outcome == "resolved")
        #expect(try day.fact(3).hiding == .snoozed(until: day.day.adding(days: 2).start))
        #expect(try day.fact(6).state == .rejected && day.fact(6).hiding == .hidden)
        #expect(try day.fact(5).state == .confirmed && day.fact(5).hiding == .hidden)
    }

    @Test func theHandOffMenuOffersTheOtherPeopleAndNotTheFounder() async throws {
        let day = try await setup()
        #expect(day.model.handOffPeople == ["Meera", "Raj"])
    }

    // MARK: Reliability to the person first

    @Test func aPersonsOpenCountOnPeopleIsShownForTheFounderOnly() async throws {
        let day = try await setup()
        let shown = Dictionary(
            uniqueKeysWithValues: day.model.people.map { ($0.name, day.model.shownOpenCount(of: $0, lens: .people)) })
        #expect(
            shown["Asha"] == 2 && shown["Meera"] == .some(nil) && shown["Raj"] == .some(nil), "the list ranks people")
    }

    @Test func aProjectsOpenCountIsShownAndATeamLineCarriesNoPersonCount() async throws {
        let day = try await setup()
        let login = try #require(day.model.projectGroups.first { $0.name == "Login" })
        #expect(day.model.shownOpenCount(of: login, lens: .projects) == 2)
        #expect(day.model.team.allSatisfy { $0.openCount == 0 })
    }

    // MARK: First run

    private func backlogged() async throws -> Setup {
        let day = try await setup()
        var settings = MorningSettings()
        settings.cutoffDays = 1
        try MorningSchedule.settingsKey.save(settings, to: day.store)
        day.clock.set(noon.addingTimeInterval(3 * 86_400))
        day.model.refresh()
        return day
    }

    @Test func theFirstListOffersToMarkFactsOlderThanNDaysAsHandled() async throws {
        let day = try await setup()
        #expect(!day.model.offersCutoff, "nothing is older than 7 days")
        let later = try await backlogged()
        #expect(later.model.offersCutoff && later.model.backlog.compactMap(\.id).sorted() == [1, 2, 3, 5, 6])
    }

    @Test func markingTheBacklogHandledClosesItInOneBulkEventAndKeepsEveryFact() async throws {
        let day = try await backlogged()
        let before = try day.store.queries.items(of: HelperSpec.team.task, since: day.day).count
        day.model.markBacklogHandled()
        #expect(day.model.sections.allSatisfy { $0.kind != .owe && $0.kind != .slipped })
        #expect(!day.model.offersCutoff && day.model.handledBatch?.olderThanDays == 1)
        #expect(try day.store.queries.items(of: HelperSpec.team.task, since: day.day).count == before)
        #expect(try day.fact(2).closed?.outcome == "handled")
        #expect(try day.store.queries.latestHandledBatch()?.surface == .today)
    }

    @Test func reopeningTheHandledBatchBringsTheListBackAndTheOfferDoesNotReturn() async throws {
        let day = try await backlogged()
        let before = day.model.needsCount
        day.model.markBacklogHandled()
        day.model.reopenHandled()
        #expect(day.model.needsCount == before && day.model.handledBatch == nil)
        #expect(!day.model.offersCutoff)
    }

    @Test func keepingTheBacklogClosesNothingAndEndsTheOffer() async throws {
        let day = try await backlogged()
        day.model.keepBacklog()
        #expect(!day.model.offersCutoff)
        #expect(try day.fact(2).closed == nil)
    }
}
