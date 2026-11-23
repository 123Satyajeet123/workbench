import Foundation
import Lines
import Testing

@testable import WorkbenchCore

/// What the extension's lines become in the app: lines that carry a site's own id are stable; lines with none are
/// named by their content and are of lower quality. An id is never made up.
@Suite struct WebLineTests {
    private func page(
        _ url: String = "https://app.slack.com/client/T1/C1", frame: String? = nil, items: [WebPage.Item]?,
        container: WebPage.Container? = WebPage.Container(value: "T1/C1", via: "url")
    ) -> WebPage {
        WebPage(
            browser: "com.brave.Browser", url: url, title: "deals", text: "words", frame: frame, items: items,
            container: container)
    }

    private func item(_ id: String?, _ text: String) -> WebPage.Item {
        WebPage.Item(id: id, via: id == nil ? nil : "id", text: text)
    }

    @Test func aLineWithASiteIdIsStableAndNamedBySiteContainerAndId() throws {
        let lines = try page(items: [item("1700000000.000100", "Term sheet is signed.")]).observedLines(
            readerVersion: "web-1")
        let line = try #require(lines.first)
        #expect(lines.count == 1 && line.quality == .stable)
        #expect(
            line.line.entity
                == (try EntityKey.web(site: "app.slack.com", container: "T1/C1", itemID: "1700000000.000100")))
    }

    @Test func anEditedLineKeepsItsEntityAndANewTextIsANewLine() throws {
        let before = try #require(
            try page(items: [item("1.1", "Close on Friday.")]).observedLines(readerVersion: "web-1").first)
        let after = try #require(
            try page(items: [item("1.1", "Close on Monday.")]).observedLines(readerVersion: "web-1").first)
        #expect(before.line.entity == after.line.entity && before.line.id != after.line.id)
    }

    @Test func aLineWithNoIdIsNamedByItsContentAtLowerQualityNeverByAMadeUpId() throws {
        let lines = try page(
            "https://feed.example/home", items: [item(nil, "Raised a seed round."), item(nil, "Raised a seed round.")],
            container: nil
        ).observedLines(readerVersion: "web-1")
        #expect(lines.count == 2, "two equal texts are two lines")
        #expect(lines.allSatisfy { $0.quality == .ephemeral && $0.quality != .stable })
        let contentKeys = try Line.screen(
            container: "https://feed.example/home", texts: ["Raised a seed round.", "Raised a seed round."],
            readerVersion: "web-1"
        ).map(\.entity)
        #expect(lines.map(\.line.entity) == contentKeys, "the key is made of the text, not of an id")
    }

    @Test func anIdWithNoContainerCannotNameALine() throws {
        let lines = try page(items: [item("1.1", "Orphan id.")], container: nil).observedLines(readerVersion: "web-1")
        let line = try #require(lines.first)
        #expect(line.quality == .ephemeral, "an id with no place is no name")
    }

    @Test func aPageWithNoItemsGivesNoLines() throws {
        #expect(try page(items: nil).observedLines(readerVersion: "web-1").isEmpty)
        #expect(try page(items: []).observedLines(readerVersion: "web-1").isEmpty)
    }
}

/// A page is kept only if the page address and the frame address are both allowed.
@Suite struct FramePolicyTests {
    private let on = CapturePolicy(switches: [.screen: true, .screenText: true])

    private func page(frame: String?) -> WebPage {
        WebPage(
            browser: "com.brave.Browser", url: "https://app.example.com/board", title: "Board",
            text: "Deck from Acme", frame: frame)
    }

    @Test func aFrameOnAnAllowedSiteIsKeptUnderThePageAddress() throws {
        let reading = try #require(page(frame: "https://widget.example.com/inside").reading(policy: on, at: t0))
        #expect(reading.container == "https://app.example.com/board" && reading.label == "app.example.com")
        #expect(page(frame: nil).reading(policy: on, at: t0) != nil)
    }

    @Test func aFrameOnAPrivateMailOrWhatsAppSiteIsNeverKeptEvenInAnAllowedPage() {
        for frame in [
            "https://netbanking.hdfcbank.com/login", "https://mail.google.com/mail/u/0/", "https://web.whatsapp.com/",
        ] {
            #expect(page(frame: frame).reading(policy: on, at: t0) == nil, "\(frame)")
        }
        var denied = on
        denied.denyList[.screen] = ["widget.example.com"]
        #expect(page(frame: "https://widget.example.com/inside").reading(policy: denied, at: t0) == nil)
    }
}
