import Foundation
import Kernel
import Lines
import Testing

@testable import WorkbenchCore

@Suite struct PageTextTests {
    private let on = CapturePolicy(switches: [.screen: true, .screenText: true]).withTestBrowser
    private let owner = Result<PersonID, any Error>.success(try! PersonID("owner-1"))
    private func page(_ url: String, title: String = "Inbox", browser: String = "com.brave.Browser") -> WebPage {
        WebPage(browser: browser, url: url, title: title, text: "Deck from Acme: seed round, 2M")
    }

    @Test func aPageIsKeptAsScreenTextLinesLabelledWithItsSiteAndWithoutItsQuery() throws {
        let reading = try #require(
            page("https://mail.example.com/mail/u/0/?tab=rm#inbox").reading(policy: on, at: t0))
        #expect(reading.container == "https://mail.example.com/mail/u/0/" && reading.label == "mail.example.com")
        #expect(reading.grant.kind == .screenText && reading.grant.label == "mail.example.com")
        #expect(reading.lines.map(\.line.text) == ["Deck from Acme: seed round, 2M"])
        #expect(reading.lines.first?.coordinate == "Inbox", "the title")
        #expect(reading.audience == AudienceDigest(owner: "me", members: [String]()), "the owner alone")
    }

    @Test func aPageIsKeptOnlyWithAnOwner() throws {
        let store = try makeStore()
        try store.savePolicy(on)
        let message = try JSONEncoder().encode(page("https://mail.example.com/"))
        let withoutOwner = PageHost.answer(message, store: store, browser: "com.brave.Browser")
        #expect(withoutOwner.kept == false && withoutOwner.error == PageHost.unknownOwner)
        #expect(PageHost.answer(message, store: store, browser: "com.brave.Browser", owner: owner).kept)
        #expect(try store.queries.pageLines(from: .distantPast, to: .distantFuture).count == 1)
    }

    @Test func noTextIsKeptWhenTheSwitchIsOffTheSiteIsPrivateOrDeniedOrTheWindowIsPrivate() {
        let textOff = CapturePolicy(switches: [.screen: true, .screenText: false]).withTestBrowser
        #expect(page("https://mail.example.com/").reading(policy: textOff, at: t0) == nil)
        #expect(
            page("https://mail.example.com/").reading(
                policy: CapturePolicy(switches: [.screenText: true]).withTestBrowser, at: t0)
                == nil
        )
        #expect(page("https://netbanking.hdfcbank.com/login").reading(policy: on, at: t0) == nil)
        var denied = on
        denied.denyList[.screen] = ["linkedin.com"]
        #expect(page("https://www.linkedin.com/in/someone").reading(policy: denied, at: t0) == nil)
        #expect(page("https://www.linkedin.com/in/someone").reading(policy: on, at: t0) != nil)
        #expect(page("https://x.com/home", title: "Home / X - Private Browsing").reading(policy: on, at: t0) == nil)
        #expect(page("https://x.com/home", browser: "com.evil.app").reading(policy: on, at: t0) == nil)
        var paused = on
        paused.mode = .paused(until: t0.addingTimeInterval(3600))
        #expect(page("https://x.com/home").reading(policy: paused, at: t0) == nil)
    }

    @Test func aPageIsKeptOnlyFromABrowserThePersonEnabled() {
        let url = "https://news.example.com/"
        #expect(page(url).reading(policy: on, at: t0) != nil, "the control")
        var noBrowser = on
        noBrowser.browsers = [:]
        #expect(page(url).reading(policy: noBrowser, at: t0) == nil)
        var another = on
        another.browsers = ["x.other": "Other"]
        #expect(page(url).reading(policy: another, at: t0) == nil, "yes to one browser is no to the next")
    }

    @Test func gmailIsNeverKeptAsAPageEvenWithScreenTextOn() throws {
        #expect(page("https://mail.google.com/mail/u/0/#inbox").reading(policy: on, at: t0) == nil)
        #expect(page("https://mail.google.com/mail/u/0/#label/Deals/FMfc").reading(policy: on, at: t0) == nil)
        let store = try makeStore()
        try store.savePolicy(on)
        let reply = PageHost.answer(
            try JSONEncoder().encode(page("https://mail.google.com/")), store: store, browser: "com.brave.Browser",
            owner: owner)
        #expect(reply == PageHost.Reply(kept: false))
        #expect(try store.queries.pageLines(from: .distantPast, to: .distantFuture).isEmpty)
    }

    @Test func whatsAppWebIsNeverKeptAsAPageEvenWithScreenTextOn() throws {
        #expect(page("https://web.whatsapp.com/").reading(policy: on, at: t0) == nil)
        #expect(page("https://web.whatsapp.com/send?phone=91").reading(policy: on, at: t0) == nil)
        #expect(page("https://whatsapp.com/").reading(policy: on, at: t0) != nil, "only the web client is excluded")
        let store = try makeStore()
        try store.savePolicy(on)
        let reply = PageHost.answer(
            try JSONEncoder().encode(page("https://web.whatsapp.com/")), store: store, browser: "com.brave.Browser",
            owner: owner)
        #expect(reply == PageHost.Reply(kept: false))
        #expect(try store.queries.pageLines(from: .distantPast, to: .distantFuture).isEmpty)
    }

    @Test func theHostKeepsAllowedPagesAndAnswersEveryFrame() throws {
        let store = try makeStore()
        try store.savePolicy(on)
        let pages = [page("https://mail.example.com/"), page("https://www.hdfcbank.com/")]
        let input = try pages.map { NativeMessage.frame(try JSONEncoder().encode($0)) }.reduce(Data(), +)
        var output = PageHost.receive(input, store: store, browser: "com.brave.Browser", owner: owner)
        var replies: [PageHost.Reply] = []
        while let (message, used) = try NativeMessage.first(in: output) {
            replies.append(try JSONDecoder().decode(PageHost.Reply.self, from: message))
            output = output.dropFirst(used)
        }
        #expect(replies.map(\.kept) == [true, false])
        #expect(try store.queries.pageLines(from: .distantPast, to: .distantFuture).count == 1)
    }

    @Test func aBrokenOrOversizeFrameStoresNothing() throws {
        let store = try makeStore()
        try store.savePolicy(on)
        let huge = Data([0xFF, 0xFF, 0xFF, 0x7F])
        #expect(throws: NativeMessage.Failure.tooLong(0x7FFF_FFFF)) { try NativeMessage.first(in: huge) }
        #expect(throws: NativeMessage.Failure.truncated) { try NativeMessage.first(in: Data([5, 0, 0, 0, 1])) }
        _ = PageHost.receive(
            huge + NativeMessage.frame(try JSONEncoder().encode(page("https://x.com/"))), store: store,
            browser: "com.brave.Browser", owner: owner)
        _ = PageHost.receive(
            NativeMessage.frame(Data("not json".utf8)), store: store, browser: "com.brave.Browser", owner: owner)
        #expect(try store.queries.pageLines(from: .distantPast, to: .distantFuture).isEmpty)
    }

    @Test func aFrameIsReadWholeOrNamedBrokenOrTheEndOfTheInput() {
        func next(_ bytes: [UInt8]) -> NativeMessage.Incoming {
            var rest = Data(bytes)
            return NativeMessage.next(read: { count in
                let chunk = rest.prefix(count)
                rest = rest.dropFirst(chunk.count)
                return Data(chunk)
            })
        }
        #expect(next([]) == .end)
        #expect(next([2, 0, 0, 0, 0x7B, 0x7D]) == .message(Data("{}".utf8)))
        #expect(next([2, 0]) == .broken(.truncated), "a header cut short")
        #expect(next([5, 0, 0, 0, 1]) == .broken(.truncated), "a body cut short")
        #expect(next([0xFF, 0xFF, 0xFF, 0x7F]) == .broken(.tooLong(0x7FFF_FFFF)))
        #expect(next([0, 0, 0x10, 0]) == .broken(.truncated), "1 MiB is the most a frame may hold, and none follows")
        #expect(next([1, 0, 0x10, 0]) == .broken(.tooLong(0x10_0001)))
    }

    private func line(_ id: Int64, _ url: String, _ text: String) -> PageLine {
        PageLine(
            id: id, lineID: Data(repeating: UInt8(id), count: 32), address: url,
            site: CapturePolicy.host(of: url) ?? "", title: "t", seenAt: t0.addingTimeInterval(Double(id)), text: text)
    }

    @Test func aMachineReadsOnlyItsNamedSitesEachTextOnceWithinTheBudget() {
        let day = [
            line(1, "https://x.com/home", "a post"),
            line(2, "https://www.linkedin.com/in/someone", "Partner at Fund"),
            line(3, "https://mail.example.com/mail/u/0/", "Deck from Acme"),
            line(4, "https://mail.example.com/mail/u/0/", "Deck from Acme"),
            line(5, "https://mail.example.com/mail/u/0/", "Intro to Bolt"),
        ]
        let read = PageLine.reading(day, sites: ["mail.example.com", "linkedin.com"])
        #expect(read.pages.map(\.text) == ["Partner at Fund", "Deck from Acme", "Intro to Bolt"])
        #expect(read.leftOut == 0)
        #expect(PageLine.reading(day, sites: []).pages.isEmpty, "no named site reads nothing")
        let tight = PageLine.reading(day, sites: ["mail.example.com"], budget: 20)
        #expect(tight.pages.map(\.text) == ["Deck from Acme"] && tight.leftOut == 1)
    }

    @Test func aTypedSiteBecomesAHost() {
        #expect(WebPage.site("https://www.LinkedIn.com/feed/") == "linkedin.com")
        #expect(WebPage.site(" mail.example.com ") == "mail.example.com")
        #expect(WebPage.site("gmail") == nil && WebPage.site("") == nil)
    }
}
