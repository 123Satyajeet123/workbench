import CaptureService
import Foundation
import SwiftUI
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// A search that answers every query with the same pages, and a fetcher that serves them by address. Both record
/// what they were asked, so a test can see that nothing was sent.
final class PageWeb: SearchProvider, PageFetching, Sendable {
    let queries = Mutex<[String]>([])
    let pages: [String: String]

    init(_ pages: [String: String]) { self.pages = pages }

    func search(_ query: String, count: Int) async throws -> [SearchHit] {
        queries.withLock { $0.append(query) }
        return pages.keys.sorted().map { SearchHit(title: "", url: URL(string: $0)!, snippet: "") }
    }

    func fetch(_ url: URL) async throws -> FetchedPage {
        FetchedPage(url: url, text: pages[url.absoluteString] ?? "")
    }
}

/// The outbound machine end to end over a scratch store: a Deal intake machine with a thesis, an Outbound machine made
/// from the template, a fake search and a scripted model. No network and no real model.
@MainActor
struct OutboundWorld {
    static let payroll =
        "Ledgerly, a Bengaluru-based payroll startup (ledgerly.example), crossed $42k MRR with a team of 38. Its founders are ex-Razorpay."
    static let fantasy = "Pitch11 is a Bengaluru-based fantasy sports app with $80k MRR and 60 people."
    static let notes = "Quill, a Pune-based note tool, has a team of 12 and has not shared its revenue."
    static let pages = [
        "https://yourstory.example/payroll": payroll, "https://inc42.example/fantasy": fantasy,
        "https://blog.example/list": notes,
    ]

    let fixture: DealFixture
    let capture: CaptureService
    let web: PageWeb
    let model: ArticleModel
    let crew: Crew
    let helper: HelperModel
    let source: OutboundSource
    var store: Store { fixture.store }

    /// `key` is the search key the session finds; nil is a Mac with no key.
    init(key: String? = "key") throws {
        fixture = try DealFixture()
        capture = try CaptureService(store: fixture.store)
        web = PageWeb(Self.pages)
        let queries =
            #"{"criteria":[{"rule":"r_in","queries":["bengaluru seed startups","india saas funding"]},{"rule":"r_mrr","queries":["startup crosses 40k MRR"]},{"rule":"r_emp","queries":["startup team of 30 hiring"]},{"rule":"r_team","queries":["ex-razorpay founders new startup"]}]}"#
        model = ArticleModel([
            "r_in (must)": queries,
            "https://yourstory.example/payroll": Self.reply(
                "Ledgerly", domain: "ledgerly.example",
                [
                    (VCFixture.india, "yes", "Bengaluru-based"), (VCFixture.mrr, "42000", "$42k MRR"),
                    (VCFixture.gambling, "no", "payroll startup"), (VCFixture.employees, "38", "a team of 38"),
                    (VCFixture.team, "yes", "ex-Razorpay"),
                ], quote: "crossed $42k MRR with a team of 38"),
            "https://inc42.example/fantasy": Self.reply(
                "Pitch11", domain: "",
                [
                    (VCFixture.india, "yes", "Bengaluru-based"), (VCFixture.mrr, "80000", "$80k MRR"),
                    (VCFixture.gambling, "yes", "fantasy sports app"), (VCFixture.employees, "60", "60 people"),
                    (VCFixture.team, "unclear", ""),
                ], quote: "fantasy sports app with $80k MRR"),
            "https://blog.example/list": Self.reply(
                "Quill", domain: "",
                [
                    (VCFixture.india, "yes", "Pune-based"), (VCFixture.mrr, "", ""),
                    (VCFixture.gambling, "no", "note tool"), (VCFixture.employees, "12", "a team of 12"),
                    (VCFixture.team, "unclear", ""),
                ], quote: "has a team of 12"),
        ])
        let (store, model, web) = (fixture.store, model, web)
        try store.saveWebSettings(WebSettings(provider: .brave))
        crew = Crew(
            store: store, capture: capture, founder: { "Aditya" },
            makeModel: { _ in RecordedModel(model, store: store) },
            notifier: FakeNotifier(),
            openWebSession: {
                try WebSession.open(store: store, key: { _ in key }, make: { _, _, _ in (web, web) })
            })
        crew.reload()
        let id = try #require(crew.create(from: .outbound, name: "Outbound"))
        helper = try #require(crew.helper(id: id))
        source = try #require(helper.source as? OutboundSource)
    }

    func switchWeb(_ on: Bool) throws { try capture.update { $0.switches[.web] = on } }

    /// The reply of the model for one page: one candidate with an answer and a quote for each rule.
    static func reply(
        _ company: String, domain: String, _ answers: [(rule: Rule, answer: String, quote: String)], quote: String
    ) -> String {
        var item: [String: Any] = VCFixture.reading(answers)
        item["company"] = company
        item["domain"] = domain
        item["sector"] = "software"
        item["cite"] = 1
        item["quote"] = quote
        let data = try? JSONSerialization.data(withJSONObject: ["items": [item]], options: [.sortedKeys])
        return String(decoding: data ?? Data(), as: UTF8.self)
    }

    var listed: [OutboundCandidate] {
        OutboundReview.list(
            source.items, criteria: helper.spec.criteria ?? Criteria(), known: source.known, now: .now)
    }

    func find() async throws {
        await helper.read()
        helper.reload()
    }
}

@MainActor
@Suite struct OutboundTests {
    @Test func aNewOutboundMachineStartsWithACopyOfDealIntakesCriteria() throws {
        let world = try OutboundWorld()
        #expect(world.helper.spec.criteria == VCFixture.thesis)
        #expect(world.crew.thesisSource(for: world.helper)?.spec.criteria == VCFixture.thesis)
        #expect(world.helper.spec.source == .webSearch && world.helper.spec.task.hasPrefix("vc.outbound-"))
    }

    @Test func withTheWebSwitchOffTheMachineIsNotReadyAndNothingIsSent() async throws {
        let world = try OutboundWorld()
        #expect(!world.helper.isReady)
        await world.helper.read()
        #expect(world.web.queries.withLock { $0 }.isEmpty)
        #expect(try world.store.queries.runs().isEmpty, "no model call")
    }

    @Test func withTheSwitchOnButNoKeyTheRunStopsBeforeAnyCallAndSaysWhy() async throws {
        let world = try OutboundWorld(key: nil)
        try world.switchWeb(true)
        await world.helper.read()
        #expect(world.helper.problem?.contains("no search key") == true)
        #expect(world.web.queries.withLock { $0 }.isEmpty)
        #expect(try world.store.queries.runs().isEmpty, "no model call")
    }

    @Test func aRunListsStartupsRankedByClassThenPointsAndKeepsItsQueriesAndCost() async throws {
        let world = try OutboundWorld()
        try world.switchWeb(true)
        try await world.find()
        #expect(world.listed.map(\.company) == ["Ledgerly", "Quill", "Pitch11"])
        #expect(world.listed.map(\.triage.rating) == [.hot, .warm, .cold])
        let run = try #require(world.source.runs.last)
        #expect(run.queries.count == 5 && run.cost.searches == 5 && run.pagesRead == 3 && run.kept == 3)
        #expect(run.cost.totalUSD > 0)
    }

    @Test func addToDealsMakesOneInboxDealLinkedToItsEvidenceAndNothingIsAddedTwice() async throws {
        let world = try OutboundWorld()
        try world.switchWeb(true)
        try await world.find()
        let top = try #require(world.listed.first)
        let deals = world.fixture.deals
        await deals.addCandidate(top.item, of: world.helper, from: world.source)
        world.helper.reload()
        let made = try #require(deals.deals.first { $0.name == "Ledgerly" })
        #expect(deals.deals.count == 1 && made.stageLabels == [ObjectTypes.deal.orderedStages[0].label])
        let linked = try #require(made.items.first)
        #expect(made.items.count == 1 && linked.item.task == world.helper.spec.task)
        #expect(
            linked.item.quote == top.item.quote && linked.item.fields[Outbound.urlField] == top.item[Outbound.urlField])
        #expect(world.listed.map(\.company) == ["Quill", "Pitch11"], "it leaves the review list")
        try await world.find()
        #expect(
            deals.deals.count == 1 && world.listed.map(\.company) == ["Quill", "Pitch11"], "a new run adds no copy")
        let stored = try world.store.queries.items(of: world.helper.spec.task, since: world.helper.today)
        let marked = try #require(stored.first { $0["company"] == "Ledgerly" })
        #expect(marked.state == .confirmed)
    }

    @Test func notAFitIsAWrongMarkWithItsReasonAndSnoozeHidesForDays() async throws {
        let world = try OutboundWorld()
        try world.switchWeb(true)
        try await world.find()
        let (first, second) = (world.listed[0], world.listed[1])
        try world.source.notAFit(first.item, reason: "founder is not full time")
        try world.source.snooze(second.item, days: 7)
        world.helper.reload()
        #expect(world.listed.map(\.company) == ["Pitch11"])
        let reasons = try world.store.queries.rejections(task: world.helper.spec.task)
        #expect(reasons.map(\.reason) == ["founder is not full time"] && reasons.first?.company == "Ledgerly")
        let stored = try world.store.queries.items(of: world.helper.spec.task, since: world.helper.today)
        #expect(stored.first { $0["company"] == "Ledgerly" }?.state == .rejected)
        #expect(stored.first { $0["company"] == "Quill" }?.state == .proposed)
        #expect(
            OutboundReview.list(
                stored, criteria: VCFixture.thesis, known: world.source.known, now: .now.addingTimeInterval(8 * 86_400)
            ).map(\.company) == ["Quill", "Pitch11"])
    }

    @Test func theWeeklySearchRunsWhenOnceAWeekHasPassedAndNotBefore() async throws {
        let now = Date.now
        #expect(!WeeklySearch(isOn: false).isDue(at: now, lastRan: nil))
        #expect(WeeklySearch(isOn: true).isDue(at: now, lastRan: nil))
        #expect(!WeeklySearch(isOn: true).isDue(at: now, lastRan: now.addingTimeInterval(-6 * 86_400)))
        #expect(WeeklySearch(isOn: true).isDue(at: now, lastRan: now.addingTimeInterval(-7 * 86_400)))
        let world = try OutboundWorld()
        try world.switchWeb(true)
        await world.helper.schedule.findIfDue()
        #expect(world.web.queries.withLock { $0 }.isEmpty, "off by default: nothing runs")
        world.helper.weekly.isOn = true
        await world.helper.schedule.findIfDue()
        let sent = world.web.queries.withLock { $0 }.count
        #expect(sent == 5)
        await world.helper.schedule.findIfDue()
        #expect(world.web.queries.withLock { $0 }.count == sent, "a second check the same week sends nothing")
    }
}
