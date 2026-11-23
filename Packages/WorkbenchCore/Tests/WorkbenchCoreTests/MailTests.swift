import CoreGraphics
import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

@Suite struct MailTests {
    private let named = CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals"]])
    private let gmail = MailContext(
        browser: "com.brave.Browser", url: "https://mail.google.com/mail/u/0/#label/Deals/FMfcgz",
        label: "Deals", threadId: "FMfcgz", messageId: "msg-1")

    private func message(_ context: MailContext? = nil, text: String = "Acme raises a 2M seed.") -> MailMessage {
        MailMessage(
            context: context ?? gmail, sender: "Ana <ana@acme.example>", subject: "Acme seed", sent: 1_789_990_000,
            text: text, attachments: ["Deck.pdf"])
    }

    private func store(policy: CapturePolicy?) throws -> Store {
        let store = try makeStore()
        if let policy { try store.savePolicy(policy) }
        return store
    }

    private func send(
        _ value: some Encodable, to store: Store, browser: String = "com.brave.Browser",
        decks: DeckAssembly = DeckAssembly()
    ) throws -> PageHost.Reply {
        PageHost.answer(try JSONEncoder().encode(value), store: store, browser: browser, decks: decks)
    }

    private func stored(_ store: Store) throws -> [MailPart] {
        try store.queries.mailParts(from: .distantPast, to: .distantFuture)
    }

    // MARK: consent

    @Test func mailNeedsItsSwitchAndANamedLabel() {
        let ask = CaptureRequest(kind: .mail, label: "Deals")
        #expect(CapturePolicy().authorize(ask, at: t0).denial == .sourceSwitchedOff)
        #expect(
            CapturePolicy(switches: [.mail: true]).authorize(ask, at: t0).denial == .labelNotAllowed,
            "a mail switch with no label named reads nothing")
        #expect(named.authorize(ask, at: t0).grant?.label == "Deals")
        #expect(named.authorize(CaptureRequest(kind: .mail, label: "Personal"), at: t0).denial == .labelNotAllowed)
        #expect(named.authorize(CaptureRequest(kind: .mail), at: t0).denial == .labelNotAllowed)
        var off = named
        off.mode = .off
        #expect(off.authorize(ask, at: t0).denial == .captureOff)
        var paused = named
        paused.mode = .paused(until: day(1))
        #expect(paused.authorize(ask, at: t0).denial == .paused)
        var privateMode = named
        privateMode.mode = .privateMode(until: day(1))
        #expect(privateMode.authorize(ask, at: t0).denial == .privateMode)
    }

    @Test func mailIsAnotherConsentKindThanPageText() {
        let pageText = CapturePolicy(switches: [.screen: true, .screenText: true], allowList: [.mail: ["Deals"]])
        #expect(pageText.authorize(CaptureRequest(kind: .mail, label: "Deals"), at: t0).denial == .sourceSwitchedOff)
        #expect(named.authorize(CaptureRequest(kind: .screenText), at: t0).denial == .sourceSwitchedOff)
    }

    // MARK: the host keeps or drops

    @Test func aMessageInTheNamedLabelIsKeptWithItsFields() throws {
        let store = try store(policy: named)
        let reply = try send(message(), to: store)
        #expect(reply == PageHost.Reply(kept: true, wantDecks: ["Deck.pdf"]))
        let part = try #require(try stored(store).first)
        #expect(part.threadID == "FMfcgz" && part.messageID == "msg-1" && part.kind == .message)
        #expect(part.sender == "Ana <ana@acme.example>" && part.subject == "Acme seed")
        #expect(part.text == "Acme raises a 2M seed." && part.label == "Deals")
        #expect(part.sentAt == Date(timeIntervalSince1970: 1_789_990_000) && part.seenAt == t0)
    }

    @Test func withMailConsentOffNothingIsStored() throws {
        for policy in [nil, CapturePolicy(allowList: [.mail: ["Deals"]]), CapturePolicy(switches: [.mail: false])] {
            let store = try store(policy: policy)
            #expect(try send(message(), to: store) == PageHost.Reply(kept: false))
            #expect(try stored(store).isEmpty)
            #expect(try store.queries.mailThreadsOpened(inLabel: "Deals").isEmpty)
        }
        let pagesOnly = try store(policy: CapturePolicy(switches: [.screen: true, .screenText: true]))
        #expect(try send(message(), to: pagesOnly).kept == false, "page text consent does not cover mail")
        #expect(try stored(pagesOnly).isEmpty)
    }

    @Test func aMessageInAnotherLabelIsDroppedByTheHost() throws {
        let store = try store(policy: named)
        var other = gmail
        other.label = "Personal"
        #expect(try send(message(other), to: store).kept == false)
        other.label = "deals"
        #expect(try send(message(other), to: store).kept == false, "the label must be the named one exactly")
        #expect(try stored(store).isEmpty)
        #expect(try store.queries.mailThreadsOpened(inLabel: "Personal").isEmpty)
    }

    @Test func mailFromAnyOtherSiteOrBrowserIsDropped() throws {
        let store = try store(policy: named)
        for (browser, url) in [
            ("com.brave.Browser", "https://evil.example/mail.google.com"),
            ("com.brave.Browser", "https://mail.google.com.evil.example/"),
            ("com.brave.Browser", "https://outlook.office.com/mail/"),
            ("com.evil.app", "https://mail.google.com/mail/u/0/"),
        ] {
            var context = gmail
            context.url = url
            #expect(try send(message(context), to: store, browser: browser).kept == false, "\(url) in \(browser)")
        }
        #expect(try stored(store).isEmpty)
    }

    @Test func aDuplicateMessageIsStoredOnce() throws {
        let store = try store(policy: named)
        #expect(try send(message(), to: store).kept)
        #expect(try send(message(), to: store).kept == false, "the second opening adds nothing")
        #expect(try stored(store).count == 1)
        #expect(try send(message(text: "changed"), to: store).kept == false, "the message id decides, not the text")
        #expect(try stored(store).map(\.text) == ["Acme raises a 2M seed."])
        var second = gmail
        second.messageId = "msg-2"
        #expect(try send(message(second, text: "Reply"), to: store).kept)
        #expect(try stored(store).count == 2)
    }

    @Test func aThreadOpenedTwiceOnADayCountsOnceAndAgainOnTheNextDay() throws {
        let now = Mutex(t0)
        let store = try Store(directory: temporaryDirectory(), clock: { now.withLock { $0 } })
        try store.savePolicy(named)
        _ = try send(message(), to: store)
        _ = try send(message(), to: store)
        var other = gmail
        other.threadId = "OtherThread"
        other.messageId = "msg-9"
        _ = try send(message(other), to: store)
        #expect(try store.queries.mailThreadsOpened(inLabel: "Deals") == [WorkDay(containing: t0): 2])
        now.withLock { $0 = day(1) }
        _ = try send(message(), to: store)
        let counts = try store.queries.mailThreadsOpened(inLabel: "Deals")
        #expect(counts[WorkDay(containing: day(1))] == 1 && counts[WorkDay(containing: t0)] == 2)
        #expect(try stored(store).count == 2, "the message rows did not grow")
    }

    @Test func theHostSaysWhichLabelsItReads() throws {
        let status = Data(#"{"type":"mail_status"}"#.utf8)
        #expect(PageHost.answer(status, store: try store(policy: named), browser: nil).labels == ["Deals"])
        #expect(PageHost.answer(status, store: try store(policy: nil), browser: nil).labels == [])
        #expect(
            PageHost.answer(
                status, store: try store(policy: CapturePolicy(allowList: [.mail: ["Deals"]])), browser: nil
            ).labels
                == [], "a label without the switch is not readable")
        #expect(
            PageHost.answer(Data(#"{"type":"nope"}"#.utf8), store: try store(policy: named), browser: nil).error != nil)
    }

    // MARK: decks

    @Test func aDeckInChunksReassemblesAndItsPagesAreStoredUnderTheMessage() throws {
        let store = try store(policy: named)
        _ = try send(message(), to: store)
        let deck = makeDeck([.text("Acme Seed Deck"), .text("Traction: 40k MRR")])
        let pieces = chunks(of: deck, name: "Deck.pdf", context: gmail, size: 700)
        #expect(pieces.count > 2, "the fixture must be cut into several chunks")
        let decks = DeckAssembly()
        let replies = try pieces.reversed().map { try send($0, to: store, decks: decks) }
        #expect(
            replies.map(\.kept) == Array(repeating: false, count: pieces.count - 1) + [true], "out of order is fine")
        let pages = try stored(store).filter { $0.kind == .deck }
        #expect(pages.map(\.page) == [1, 2])
        #expect(pages.map(\.text) == ["Acme Seed Deck", "Traction: 40k MRR"])
        #expect(pages.allSatisfy { $0.name == "Deck.pdf" && $0.sender == "Ana <ana@acme.example>" })
        #expect(try send(message(), to: store).wantDecks == [], "the host has the deck: it does not ask again")
        for piece in pieces { _ = try send(piece, to: store, decks: decks) }
        #expect(try stored(store).filter { $0.kind == .deck }.count == 2, "a deck sent twice is stored once")
    }

    @Test func aDeckMissingAChunkStoresNothing() throws {
        let store = try store(policy: named)
        _ = try send(message(), to: store)
        let pieces = chunks(of: makeDeck([.text("Acme Seed Deck")]), name: "Deck.pdf", context: gmail, size: 700)
        let decks = DeckAssembly()
        for piece in pieces.dropLast() { _ = try send(piece, to: store, decks: decks) }
        #expect(try stored(store).filter { $0.kind == .deck }.isEmpty)
    }

    @Test func aDeckChunkWithConsentOffOrForTheWrongLabelOrWithNoStoredMessageIsDropped() throws {
        let deck = makeDeck([.text("Acme Seed Deck")])
        let pieces = chunks(of: deck, name: "Deck.pdf", context: gmail, size: 700)

        let off = try store(policy: named)
        _ = try send(message(), to: off)
        try off.savePolicy(CapturePolicy())
        for piece in pieces { #expect(try send(piece, to: off).kept == false) }
        #expect(try stored(off).filter { $0.kind == .deck }.isEmpty, "consent withdrawn after the message")

        let wrong = try store(policy: named)
        _ = try send(message(), to: wrong)
        var other = gmail
        other.label = "Personal"
        for piece in chunks(of: deck, name: "Deck.pdf", context: other, size: 700) {
            #expect(try send(piece, to: wrong).kept == false)
        }
        #expect(try stored(wrong).filter { $0.kind == .deck }.isEmpty)

        let unknown = try store(policy: named)
        for piece in pieces { #expect(try send(piece, to: unknown).kept == false) }
        #expect(try stored(unknown).isEmpty, "a deck of a message the host never kept")
    }

    @Test func badChunksAreRefused() throws {
        let decks = DeckAssembly()
        let good = DeckChunk(
            context: gmail, name: "Deck.pdf", index: 0, count: 1, data: Data("x".utf8).base64EncodedString())
        #expect(decks.add(good) != nil)
        var tooMany = good
        tooMany.count = DeckChunk.maximumCount + 1
        var outOfRange = good
        outOfRange.index = 1
        var notBase64 = good
        notBase64.data = "***"
        for bad in [tooMany, outOfRange, notBase64] { #expect(decks.add(bad) == nil) }
    }

    @Test func aPageWithNoTextLayerIsReadByVisionAndAPageWithTextIsNot() throws {
        let deck = makeDeck([.text("Cover page text"), .picture("Revenue 40k MRR"), .text("")])
        let pages = DeckText.pages(in: deck)
        #expect(pages.map(\.page) == [1, 2], "a blank page adds nothing")
        try #require(pages.count == 2)
        #expect(pages[0].text == "Cover page text")
        #expect(pages[1].text.contains("Revenue 40k MRR"), "recognized from the picture: \(pages[1].text)")
        #expect(DeckText.pages(in: Data("not a pdf".utf8)).isEmpty)
    }

    @Test func recognizedTextComesFromTheWordsInAPicture() {
        #expect(ImageText.recognize(picture(of: "Build 4.1.11 passed")).contains("Build 4.1.11 passed"))
    }

    // MARK: reading

    @Test func theMachineReadsOneLinePerMessageAndOnePerDeckPage() throws {
        let store = try store(policy: named)
        _ = try send(message(), to: store)
        for piece in chunks(of: makeDeck([.text("Slide one")]), name: "Deck.pdf", context: gmail, size: 100_000) {
            _ = try send(piece, to: store)
        }
        let reading = MailPart.reading(try stored(store), labels: ["Deals"])
        let lines = reading.parts.compactMap(\.evidence)
        #expect(
            lines.map(\.line) == [
                "Ana <ana@acme.example> — Acme seed: Acme raises a 2M seed.",
                "Ana <ana@acme.example> — Acme seed — Deck.pdf page 1: Slide one",
            ])
        #expect(Set(lines.map(\.id)).count == 2, "every line has its own number")
        #expect(lines[1].quotable == ["Slide one"])
    }

    @Test func aReadingKeepsOnlyTheNamedLabelsEachTextOnceWithinTheBudget() {
        func part(_ id: Int64, label: String = "Deals", text: String, thread: String = "t") -> MailPart {
            MailPart(
                id: id, threadID: thread, messageID: "m\(id)", label: label, sender: "a", subject: "s", sentAt: t0,
                seenAt: t0, text: text)
        }
        let parts = [
            part(1, text: "first"), part(2, label: "Personal", text: "private"), part(3, text: "first"),
            part(4, text: "second"), part(5, text: "third"),
        ]
        #expect(MailPart.reading(parts, labels: ["Deals"]).parts.map(\.id) == [1, 4, 5])
        let tight = MailPart.reading(parts, labels: ["Deals"], budget: 11)
        #expect(tight.parts.map(\.id) == [1, 4] && tight.leftOut == 1)
        #expect(MailPart.reading(parts, labels: []).parts.isEmpty)
    }

    // MARK: deletion

    @Test func deletingTheMailKindRemovesItsPartsAndOpens() throws {
        let store = try store(policy: named)
        _ = try send(message(), to: store)
        try store.delete(.kind(.mail, before: nil))
        #expect(try stored(store).isEmpty)
        #expect(try store.queries.mailThreadsOpened(inLabel: "Deals").isEmpty)
    }

    @Test func deletingBeforeACutoffKeepsLaterMail() throws {
        let now = Mutex(t0)
        let store = try Store(directory: temporaryDirectory(), clock: { now.withLock { $0 } })
        try store.savePolicy(named)
        _ = try send(message(), to: store)
        now.withLock { $0 = day(3) }
        var later = gmail
        later.messageId = "msg-2"
        later.threadId = "Later"
        _ = try send(message(later, text: "later mail"), to: store)
        try store.delete(.kind(.mail, before: day(1)))
        #expect(try stored(store).map(\.text) == ["later mail"])
        #expect(try store.queries.mailThreadsOpened(inLabel: "Deals").keys.sorted() == [WorkDay(containing: day(3))])
    }
}
