import Foundation
import Kernel
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
        try store.savePolicy(
            CapturePolicy(
                switches: [.screen: true, .screenText: true], browsers: ["com.brave.Browser": "Brave Browser"]))
        for (url, text) in [
            ("https://mail.example.com/mail/u/0/", "Acme: raising a 2M seed, deck attached"),
            ("https://x.com/home", "a post about cats"),
        ] {
            let page = WebPage(browser: "com.brave.Browser", url: url, title: "Inbox", text: text)
            let reply = PageHost.answer(
                try JSONEncoder().encode(page), store: store, browser: "com.brave.Browser",
                owner: .success(try PersonID("test-owner")))
            #expect(reply.kept)
        }
        let gmail = try #require(
            try store.queries.pageLines(from: .distantPast, to: .distantFuture).first { $0.text.contains("Acme") }?.id)
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

        try source.choose("https://www.mail.example.com/, not-a-site")
        #expect(source.sites == ["mail.example.com"])
        scout.reload()
        #expect(source.pageReading.pages.count == 1)
        await scout.read()
        let input = try #require(scripted.inputs.withLock { $0.first })
        #expect(input.contains("mail.example.com — Inbox: Acme: raising a 2M seed"))
        #expect(!input.contains("cats"))
        #expect(scout.items.map(\.quote) == ["raising a 2M seed"])
        #expect(
            try store.queries.numbersRead(by: machine.task, among: [gmail]) == [gmail],
            "the run recorded the page line in its window")
        #expect(try PageSource(store: store, task: machine.task).sites == ["mail.example.com"], "the sites are kept")
    }

    @Test func mochiCanBuildAPageReaderShownAsATable() {
        #expect(MachineTemplate.all.contains(.pages))
        #expect(Array(HelperSpec.pages.views.keys) == ["table"])
    }
}
