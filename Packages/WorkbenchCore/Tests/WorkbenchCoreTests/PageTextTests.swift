import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct PageTextTests {
    private let on = CapturePolicy(switches: [.screen: true, .screenText: true])
    private func page(_ url: String, title: String = "Inbox", browser: String = "com.brave.Browser") -> WebPage {
        WebPage(browser: browser, url: url, title: title, text: "Deck from Acme: seed round, 2M")
    }

    @Test func aPageIsKeptAsScreenTextWithoutItsQuery() throws {
        let batch = try #require(page("https://mail.google.com/mail/u/0/?tab=rm#inbox").batch(policy: on, at: t0))
        let kept = try #require(batch.activities.first)
        #expect(batch.activities.count == 1 && kept.kind == .text)
        #expect(kept.document == "https://mail.google.com/mail/u/0/" && kept.app == "Brave Browser")
        #expect(kept.text == "Deck from Acme: seed round, 2M")
    }

    @Test func noTextIsKeptWhenTheSwitchIsOffTheSiteIsPrivateOrDeniedOrTheWindowIsPrivate() {
        let textOff = CapturePolicy(switches: [.screen: true, .screenText: false])
        #expect(page("https://mail.google.com/").batch(policy: textOff, at: t0) == nil)
        #expect(
            page("https://mail.google.com/").batch(policy: CapturePolicy(switches: [.screenText: true]), at: t0) == nil)
        #expect(page("https://netbanking.hdfcbank.com/login").batch(policy: on, at: t0) == nil)
        var denied = on
        denied.denyList[.screen] = ["linkedin.com"]
        #expect(page("https://www.linkedin.com/in/someone").batch(policy: denied, at: t0) == nil)
        #expect(page("https://www.linkedin.com/in/someone").batch(policy: on, at: t0) != nil)
        #expect(page("https://x.com/home", title: "Home / X - Private Browsing").batch(policy: on, at: t0) == nil)
        #expect(page("https://x.com/home", browser: "com.evil.app").batch(policy: on, at: t0) == nil)
        var paused = on
        paused.mode = .paused(until: t0.addingTimeInterval(3600))
        #expect(page("https://x.com/home").batch(policy: paused, at: t0) == nil)
    }

    @Test func theHostKeepsAllowedPagesAndAnswersEveryFrame() throws {
        let store = try makeStore()
        try store.savePolicy(on)
        let pages = [page("https://mail.google.com/"), page("https://www.hdfcbank.com/")]
        let input = try pages.map { NativeMessage.frame(try JSONEncoder().encode($0)) }.reduce(Data(), +)
        var output = PageHost.receive(input, store: store)
        var replies: [PageHost.Reply] = []
        while let (message, used) = try NativeMessage.first(in: output) {
            replies.append(try JSONDecoder().decode(PageHost.Reply.self, from: message))
            output = output.dropFirst(used)
        }
        #expect(replies.map(\.kept) == [true, false])
        #expect(try store.queries.activities(since: t0.addingTimeInterval(-1)).compactMap(\.text).count == 1)
    }

    @Test func aBrokenOrOversizeFrameStoresNothing() throws {
        let store = try makeStore()
        try store.savePolicy(on)
        let huge = Data([0xFF, 0xFF, 0xFF, 0x7F])
        #expect(throws: NativeMessage.Failure.tooLong(0x7FFF_FFFF)) { try NativeMessage.first(in: huge) }
        #expect(throws: NativeMessage.Failure.truncated) { try NativeMessage.first(in: Data([5, 0, 0, 0, 1])) }
        _ = PageHost.receive(huge + NativeMessage.frame(try JSONEncoder().encode(page("https://x.com/"))), store: store)
        _ = PageHost.receive(NativeMessage.frame(Data("not json".utf8)), store: store)
        #expect(try store.queries.activities(since: t0.addingTimeInterval(-1)).isEmpty)
    }

    private func text(_ url: String, _ text: String, at offset: Double, bundle: String = "com.brave.Browser")
        -> Activity
    {
        Activity(
            at: t0.addingTimeInterval(offset), kind: .text, app: "Brave Browser", bundleID: bundle, title: "t",
            document: url, text: text)
    }

    @Test func aMachineReadsOnlyItsNamedSitesEachTextOnceWithinTheBudget() {
        let day = [
            text("https://mail.google.com/mail/u/0/", "Deck from Acme", at: 3),
            text("https://mail.google.com/mail/u/0/", "Deck from Acme", at: 4),
            text("https://www.linkedin.com/in/someone", "Partner at Fund", at: 2),
            text("https://x.com/home", "a post", at: 1),
            text("https://mail.google.com/mail/u/0/", "Intro to Bolt", at: 5),
            text("file:///Users/me/notes.txt", "mail.google.com", at: 6, bundle: "com.apple.TextEdit"),
        ]
        let read = WebPage.reading(day, sites: ["mail.google.com", "linkedin.com"])
        #expect(read.pages.compactMap(\.text) == ["Partner at Fund", "Deck from Acme", "Intro to Bolt"])
        #expect(read.leftOut == 0)
        #expect(WebPage.reading(day, sites: []).pages.isEmpty, "no named site reads nothing")
        let tight = WebPage.reading(day, sites: ["mail.google.com"], budget: 20)
        #expect(tight.pages.compactMap(\.text) == ["Deck from Acme"] && tight.leftOut == 1)
    }

    @Test func aTypedSiteBecomesAHost() {
        #expect(WebPage.site("https://www.LinkedIn.com/feed/") == "linkedin.com")
        #expect(WebPage.site(" mail.google.com ") == "mail.google.com")
        #expect(WebPage.site("gmail") == nil && WebPage.site("") == nil)
    }
}
