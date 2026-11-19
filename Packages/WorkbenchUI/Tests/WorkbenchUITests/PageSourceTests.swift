import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct PageSourceTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    @Test func aPageMachineReadsNothingUntilItsSitesAreNamedThenOnlyThoseSites() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        try store.savePolicy(CapturePolicy(switches: [.screen: true, .screenText: true]))
        for (url, text) in [
            ("https://mail.google.com/mail/u/0/", "Acme: raising a 2M seed, deck attached"),
            ("https://x.com/home", "a post about cats"),
        ] {
            let page = WebPage(browser: "com.brave.Browser", url: url, title: "Inbox", text: text)
            try store.record(try #require(page.batch(policy: try store.currentPolicy(), at: now)))
        }
        let gmail = try #require(
            try store.queries.activities(since: .distantPast).first { $0.text?.contains("Acme") == true }?.id)
        let scripted = ScriptedModel(
            #"{"items":[{"title":"Acme seed round","who":"Acme","next":"Reply","cite":\#(gmail),"quote":"raising a 2M seed"}]}"#
        )
        let machine = try store.createMachine(from: .pages, name: "Scout")
        let source = try PageSource(store: store, task: machine.task)
        let scout = HelperModel(
            machine: machine, source: source, store: store,
            makeModel: { _ in RecordedModel(scripted, store: store) }, notifier: FakeNotifier())

        #expect(!scout.isReady)
        await scout.read()
        #expect(scripted.inputs.withLock { $0.isEmpty }, "no named site, no read")

        try source.choose("https://www.mail.google.com/, not-a-site")
        #expect(source.sites == ["mail.google.com"])
        scout.reload()
        #expect(source.pageReading.pages.count == 1)
        await scout.read()
        let input = try #require(scripted.inputs.withLock { $0.first })
        #expect(input.contains("mail.google.com — Inbox: Acme: raising a 2M seed"))
        #expect(!input.contains("cats"))
        #expect(scout.items.map(\.quote) == ["raising a 2M seed"])
        #expect(try PageSource(store: store, task: machine.task).sites == ["mail.google.com"], "the sites are kept")
    }

    @Test func mochiCanBuildAPageReaderShownAsATable() {
        #expect(MachineTemplate.all.contains(.pages))
        #expect(Array(HelperSpec.pages.views.keys) == ["table"])
    }

    @Test func dealIntakeRatesEachPitchByTheInvestorsCriteriaAndKeepsOnlyAllowedRatings() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        try store.savePolicy(CapturePolicy(switches: [.screen: true, .screenText: true]))
        let page = WebPage(
            browser: "com.brave.Browser", url: "https://mail.google.com/mail/u/0/", title: "Inbox",
            text: "Acme (fintech) is raising a 2M seed, 40k MRR. Bolt: we build toys, pre-seed.")
        try store.record(try #require(page.batch(policy: try store.currentPolicy(), at: now)))
        let id = try #require(try store.queries.activities(since: .distantPast).first?.id)
        let reply = """
            {"items":[
            {"company":"Acme","sector":"fintech","stage":"seed","from":"","rating":"hot","why":"revenue","cite":\(id),"quote":"Acme (fintech) is raising a 2M seed"},
            {"company":"Bolt","sector":"toys","stage":"pre-seed","from":"","rating":"cold","why":"?","cite":\(id),"quote":"Bolt: we sell toys"}]}
            """
        let scripted = ScriptedModel(reply)
        let machine = try store.createMachine(from: .dealIntake, name: "Deal intake")
        let source = try PageSource(store: store, task: machine.task)
        try source.choose("mail.google.com")
        let intake = HelperModel(
            machine: machine, source: source, store: store,
            makeModel: { _ in RecordedModel(scripted, store: store) }, notifier: FakeNotifier())
        await intake.read()
        #expect(intake.items.map { $0["company"] } == ["Acme"])
        #expect(intake.items.first?["rating"] == "hot" && intake.items.first?["why"] == "revenue")
        #expect(intake.phase == .read(kept: 1, dropped: 1))
        #expect(MachineTemplate.all.contains(.dealIntake) && !MachineTemplate.seeded.contains(.dealIntake))
    }
}
