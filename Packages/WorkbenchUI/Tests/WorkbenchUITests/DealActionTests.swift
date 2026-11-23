import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct DealActionTests {
    private let friday = WorkDay("2026-11-27")!

    @Test func actionRequiredOpensOneDatedFactTodayListsItAndDoneMovesTheDealOn() async throws {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme", reading: VCFixture.hot)
        fixture.deals.requireAction(deal, what: "Get the cap table from the founder", due: friday)

        #expect(fixture.deals.deals(in: dealStage("Action required")).map(\.id) == [deal.id])
        let open = try fixture.store.queries.openDealActions()
        #expect(open.count == 1 && open[0].dueDay == friday && open[0]["deal"] == deal.id)
        #expect(fixture.deals.digests[deal.id]?.action?.id == open[0].id)

        let today = TodayModel(store: fixture.store, crew: fixture.crew)
        let need = try #require(today.needs.first { $0.item.task == DealAction.task })
        #expect(need.reason == .asks && today.title(of: need.item) == "Get the cap table from the founder")

        today.perform(.done, on: [need.item], text: "Done")
        fixture.deals.refresh()
        #expect(try fixture.store.queries.openDealActions().isEmpty)
        #expect(try fixture.store.queries.dealActions(of: deal.id).first?.closed?.outcome == "done")
        #expect(fixture.deals.deals(in: dealStage("In conversation")).map(\.id) == [deal.id])
        #expect(fixture.deals.deals(in: dealStage("Action required")).isEmpty)
        #expect(
            fixture.deals.deal(deal.id)?.history.filter { $0.kind == .stage }.map {
                ObjectTypes.deal.resolveStage($0.text).label
            }
                == ["Inbox", "Action required", "In conversation"], "the move on is a stage event")
    }

    @Test func doneOnTheDealsOwnButtonDoesTheSameAsDoneOnToday() async throws {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme", reading: VCFixture.hot)
        fixture.deals.requireAction(deal, what: "Get the cap table", due: friday)
        fixture.deals.finishAction(of: try #require(fixture.deals.deal(deal.id)))
        #expect(fixture.deals.deals(in: dealStage("In conversation")).map(\.id) == [deal.id])
        #expect(fixture.deals.digests[deal.id]?.action == nil)
    }

    @Test func aPlainMoveCannotEnterActionRequiredAndLeavingItByHandDropsTheAction() async throws {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme", reading: VCFixture.hot)
        fixture.deals.move(deal, to: dealStage("Action required"))
        #expect(fixture.deals.deals(in: dealStage("Inbox")).map(\.id) == [deal.id], "no fact, so no stage")

        fixture.deals.requireAction(deal, what: "  ", due: friday)
        #expect(fixture.deals.deals(in: dealStage("Action required")).isEmpty, "an empty ask changes nothing")

        fixture.deals.requireAction(deal, what: "Get the cap table", due: friday)
        fixture.deals.move(try #require(fixture.deals.deal(deal.id)), to: dealStage("Rejected"))
        #expect(fixture.deals.deals(in: dealStage("Rejected")).map(\.id) == [deal.id])
        #expect(try fixture.store.queries.openDealActions().isEmpty)
        #expect(try fixture.store.queries.dealActions(of: deal.id).first?.closed?.outcome == "dropped")
        #expect(
            fixture.deals.deals(in: dealStage("In conversation")).isEmpty, "a dropped action does not move the deal on")
    }

    @Test func theCardShowsTheClassItsWhyTheOwnerAndTheOpenAction() async throws {
        let fixture = try DealFixture()
        let hot = try await fixture.deal("Acme", reading: VCFixture.hot)
        let cold = try await fixture.deal("Bet Fantasy", reading: VCFixture.breaker)
        fixture.deals.claim(hot)
        fixture.deals.requireAction(hot, what: "Get the cap table", due: friday)
        #expect(fixture.deals.digests[hot.id]?.triage?.rating == .hot)
        #expect(fixture.deals.digests[cold.id]?.triage?.rating == .cold)
        #expect(fixture.deals.deal(hot.id)?.holder == "Aditya")
        #expect(fixture.deals.digests[cold.id]?.action == nil)
    }

    @Test func theStripNamesTheMachinesTheirPrecisionTheRuleAndWhatSentinelWatches() async throws {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme", reading: VCFixture.hot, mark: .confirmed)
        var digest = try #require(fixture.deals.digests[deal.id])
        var rows = AutomationStrip.rows(for: digest, runs: try fixture.store.queries.runs(), quality: [], now: .now)
        #expect(rows.map(\.name) == ["Deal intake"] && rows[0].role == "Reads and rates")
        #expect(rows[0].rule?.hasPrefix("Rated hot by: ") == true)
        #expect(rows[0].lastRun.hasPrefix("Last read ") && rows[0].nextRun == "Reads when you press Read")
        #expect(rows[0].precision.contains("runs on its own") || rows[0].precision.contains("before it runs"))

        fixture.deals.requireAction(deal, what: "Get the cap table", due: friday)
        digest = try #require(fixture.deals.digests[deal.id])
        rows = AutomationStrip.rows(for: digest, runs: [], quality: [], now: .now)
        #expect(rows.map(\.name) == ["Deal intake", "Sentinel"] && rows[1].role == "Watches the action")
        #expect(rows[1].lastRun == "Has not read yet")
    }

    @Test func theRibbonAndTheTimelineCountWhatHappenedAndAMachineRowIsMarked() async throws {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme", reading: VCFixture.hot, source: .whatsapp, mark: .confirmed)
        fixture.deals.move(deal, to: dealStage("Screen"))
        fixture.deals.requireAction(try #require(fixture.deals.deal(deal.id)), what: "Get the cap table", due: friday)
        fixture.deals.finishAction(of: try #require(fixture.deals.deal(deal.id)))

        let story = try #require(fixture.deals.digests[deal.id]).story
        #expect(
            story.ribbon
                == DealStory.Ribbon(
                    sources: ["WhatsApp"], rating: .hot, mark: .confirmed, moves: 3, actionsOpened: 1,
                    actionsClosed: 1))
        #expect(story.ribbon.words.first == "From WhatsApp")
        #expect(story.entries.filter(\.isMachine).map(\.text) == ["Rated hot by the criteria"])
        #expect(story.entries.contains { $0.kind == .marked && $0.text == "Marked the reading right" })
        #expect(story.entries.map(\.at) == story.entries.map(\.at).sorted())
    }

    @Test func theNextReadFollowsTheReadingHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        }
        let watch = WatchSchedule(isOn: true, everyMinutes: 60, fromHour: 9, untilHour: 22)
        #expect(WatchSchedule().nextRun(after: nil, now: at(20, 10), calendar: calendar) == nil, "off: no next read")
        #expect(watch.nextRun(after: at(20, 10), now: at(20, 10), calendar: calendar) == at(20, 11))
        #expect(watch.nextRun(after: nil, now: at(20, 7), calendar: calendar) == at(20, 9), "before the hours")
        #expect(watch.nextRun(after: at(20, 21), now: at(20, 21), calendar: calendar) == at(21, 9), "after the hours")
        #expect(watch.nextRun(after: at(20, 8), now: at(20, 15), calendar: calendar) == at(20, 15), "overdue: now")
    }
}
