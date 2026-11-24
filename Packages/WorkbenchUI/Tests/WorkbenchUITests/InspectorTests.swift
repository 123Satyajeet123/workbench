import AppKit
import CaptureService
import Foundation
import LocalSources
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// What the inspector promises: the proof is the stored lines the run read, the cited lines and the quote are marked,
/// the place is held while the lines load, and nothing in it is a guess.
@Suite struct InspectorTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private let reply =
        #"{"items":[{"person":"Asha","project":"Login","kind":"done","text":"Login API","when":{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""},"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":@login API done@,"quote":"login API done"}]}"#

    private struct Scene {
        let store: Store
        let crew: Crew
        let team: HelperModel
        let source: WhatsAppSource
        let today: TodayModel
        let proof: ProofModel
        let item: Item
    }

    private func read() async throws -> Scene {
        let now = noon
        let store = try scratchStore(clock: { now })
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let model = ScriptedModel(reply)
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" },
            makeModel: { _ in RecordedModel(model, store: store) }, notifier: FakeNotifier(),
            whatsAppContainer: try whatsApp(at: noon))
        let team = try #require(crew.factKeepers.first)
        let source = try #require(team.source as? WhatsAppSource)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        await team.read()
        let today = TodayModel(store: store, crew: crew)
        let proof = ProofModel(today: today, crew: crew, store: store, locale: Locale(identifier: "en_GB"))
        return Scene(
            store: store, crew: crew, team: team, source: source, today: today, proof: proof,
            item: try #require(team.items.first))
    }

    // MARK: lines

    @Test func theProofIsTheStoredLinesAroundTheFactAndOnlyTheCitedOneIsCited() async throws {
        let scene = try await read()
        await scene.proof.load(scene.item)
        guard case .lines(let lines) = scene.proof.card(for: scene.item).proof else {
            Issue.record("the proof did not load: \(scene.proof.phase)")
            return
        }
        let stored = try await scene.source.proof(of: scene.item, reach: ProofModel.reach)
        #expect(lines.map(\.id) == stored.map(\.id), "the same stored lines as the Today list reads")
        #expect(lines.filter(\.isCited).map(\.words) == ["login API done"])
        #expect(lines.filter(\.isCited).map(\.sender) == ["Asha"])
        #expect(lines.count > 1 && lines.contains { !$0.isCited })
        #expect(lines.allSatisfy { $0.time != nil })
    }

    @Test func aFactWhoseLinesWereErasedShowsAPlainNoticeAndNoLines() async throws {
        let scene = try await read()
        let chat = try #require(scene.source.chat)
        try WhatsAppSource.stopReading(chat, among: [scene.source], capture: try CaptureService(store: scene.store))
        await scene.proof.load(scene.item)
        let card = scene.proof.card(for: scene.item)
        #expect(card.proof == .notice(InspectorWords.notFound))
        #expect(InspectorWords.notFound == "The lines this came from are not here any more.")
        #expect(scene.proof.lines.isEmpty)
    }

    @Test func aDeletedMessageSaysSoInWordsWhenItsLinesAreGone() async throws {
        let scene = try await read()
        var deleted = scene.item
        deleted.isSourceDeleted = true
        deleted.quote = ""
        deleted.citeFirst = 9_999
        deleted.citeLast = 9_999
        deleted.run = nil
        await scene.proof.load(deleted)
        #expect(scene.proof.card(for: deleted).proof == .notice(InspectorWords.deleted))
        var other = deleted
        other.isSourceDeleted = false
        await scene.proof.load(other)
        #expect(scene.proof.card(for: other).proof == .notice(InspectorWords.notFound))
    }

    @Test func aFactThatCitesNoLineShowsItsQuoteAndReadsNothing() async throws {
        let scene = try await read()
        var typed = scene.item
        typed.citeFirst = 0
        typed.citeLast = 0
        let reads = Counter()
        let proof = ProofModel(
            crew: scene.crew, store: scene.store, title: { _ in "" },
            lines: { _ in
                reads.count += 1
                return []
            })
        await proof.load(typed)
        #expect(proof.card(for: typed).proof == .quote(typed.quote))
        #expect(reads.count == 0)
        var web = scene.item
        web.source = .web
        await proof.load(web)
        #expect(proof.card(for: web).proof == .quote(web.quote))
        #expect(reads.count == 0)
        await proof.load(scene.item)
        #expect(reads.count == 1, "a fact that cites a chat line does read it")
    }

    @Test func aReadThatFailsShowsAProblemAndTheNextLoadTriesAgain() async throws {
        let scene = try await read()
        let attempts = Counter()
        let line = ChatLine(id: scene.item.citeFirst, time: noon, text: "Asha: login API done", isCited: true)
        let proof = ProofModel(
            crew: scene.crew, store: scene.store, title: { _ in "" },
            lines: { _ in
                attempts.count += 1
                if attempts.count == 1 { throw CocoaError(.fileReadNoPermission) }
                return [line]
            })
        await proof.load(scene.item)
        guard case .problem(let text) = proof.card(for: scene.item).proof else {
            Issue.record("a failed read shows no problem")
            return
        }
        #expect(text.hasPrefix("Could not read the chat: "))
        await proof.load(scene.item)
        #expect(
            proof.card(for: scene.item).proof
                == .lines(ProofEntry.lines([line], of: scene.item, DateWords(now: scene.store.clock()))))
        #expect(attempts.count == 2)
    }

    @Test func aFactShowsPlaceholdersUntilItsOwnLinesHaveLoaded() async throws {
        let scene = try await read()
        var other = scene.item
        other.id = 999
        other.citeFirst += 3
        other.citeLast += 3
        await scene.proof.load(scene.item)
        #expect(
            scene.proof.card(for: other).proof == .loading(rows: ProofModel.placeholderRows(for: other)),
            "the lines of the first fact are not shown under the second")
        guard case .lines = scene.proof.card(for: scene.item).proof else {
            Issue.record("the loaded fact lost its lines")
            return
        }
    }

    @Test func aMarkOrADueChangeReadsTheHistoryAgainAndNotTheChatLines() async throws {
        let scene = try await read()
        let reads = Counter()
        let proof = ProofModel(
            crew: scene.crew, store: scene.store, locale: Locale(identifier: "en_GB"), title: { _ in "" },
            lines: { _ in
                reads.count += 1
                return [ChatLine(id: scene.item.citeFirst, time: nil, text: "Asha: login API done", isCited: true)]
            })
        await proof.load(scene.item)
        #expect(!proof.card(for: scene.item).history.contains { $0.hasPrefix("You marked it") })
        try scene.store.mark(item: try #require(scene.item.id), as: .confirmed)
        var marked = scene.item
        marked.state = .confirmed
        await proof.load(marked)
        #expect(proof.card(for: marked).history.contains { $0.hasPrefix("You marked it right on") })
        #expect(reads.count == 1, "the same lines are not read again")
        var moved = marked
        moved.citeFirst += 1
        moved.citeLast += 1
        await proof.load(moved)
        #expect(reads.count == 2, "other cited lines are read")
    }

    @Test func aSlowReadOfAnEarlierFactNeverReplacesTheLinesOfTheFactNowOpen() async throws {
        let scene = try await read()
        let slow = Gate()
        let first = ChatLine(id: 1, time: nil, text: "Asha: first", isCited: true)
        let second = ChatLine(id: 2, time: nil, text: "Asha: second", isCited: true)
        let proof = ProofModel(
            crew: scene.crew, store: scene.store, title: { _ in "" },
            lines: { item in
                if item.id == 1 { await slow.wait() }
                return [item.id == 1 ? first : second]
            })
        var early = scene.item
        early.id = 1
        var late = scene.item
        late.id = 2
        late.citeFirst += 5
        late.citeLast += 5
        let earlyLoad = Task { await proof.load(early) }
        await Task.yield()
        await proof.load(late)
        await slow.open()
        await earlyLoad.value
        #expect(
            proof.card(for: late).proof
                == .lines(ProofEntry.lines([second], of: late, DateWords(now: scene.store.clock()))))
        #expect(proof.lines == [second])
    }

    // MARK: words

    private func item(
        source: SourceKind = .whatsapp, cite: Int64 = 7, quote: String = "quote", span: QuoteSpan? = nil,
        fields: [String: String] = [:], run: RunID? = 1, dueDay: String? = nil
    ) -> Item {
        Item(
            id: 1, task: HelperSpec.team.task, day: WorkDay(containing: noon), scope: teamJID, source: source,
            citeFirst: cite, citeLast: cite, start: noon, end: noon, fields: fields, quote: quote, run: run,
            quoteSpan: span,
            due: dueDay.flatMap { WorkDay($0) }.map {
                Due(utc: $0.start, zone: TimeZone.current.identifier, source: .stated, precision: .day)
            })
    }

    @Test func aWhatsAppLineIsSplitIntoSenderAndWordsAndOtherSourcesAreNot() {
        #expect(ProofEntry.parts(of: "Asha: ok: done", from: .whatsapp) == ("Asha", "ok: done"))
        #expect(ProofEntry.parts(of: "[Family] Dad: dinner", from: .whatsapp) == ("Dad", "dinner"))
        #expect(ProofEntry.parts(of: "Kabir (founder): 👍", from: .whatsapp) == ("Kabir (founder)", "👍"))
        #expect(ProofEntry.parts(of: "no sender here", from: .whatsapp) == (nil, "no sender here"))
        let long = String(repeating: "a", count: ProofEntry.longestSender + 1) + ": words"
        #expect(ProofEntry.parts(of: long, from: .whatsapp) == (nil, long), "a long text with a colon is not a sender")
        #expect(ProofEntry.parts(of: "Mail — Subject: body", from: .mail) == (nil, "Mail — Subject: body"))
    }

    private func marked(_ line: ProofEntry) -> [String] {
        let text = line.text(scale: 1, quoteFill: .yellow)
        return text.runs.filter { $0.backgroundColor != nil }.map { String(text[$0.range].characters) }
    }

    private func span(of quote: String, in words: String, line: Int64 = 7) -> QuoteSpan {
        let scalars = Array(words.nfc.unicodeScalars)
        let quoteScalars = Array(quote.nfc.unicodeScalars)
        let start = (0...(scalars.count - quoteScalars.count)).first {
            scalars[$0..<($0 + quoteScalars.count)] == quoteScalars[...]
        }!
        return QuoteSpan(line: line, part: 0, start: start, end: start + quoteScalars.count)
    }

    @Test(arguments: [
        ("Asha: kal tak review bhej dungi, pakka", "review bhej dungi"),
        ("Dev: कल तक भेज दूँगा 👍 पक्का", "भेज दूँगा 👍"),
        ("Dev: cafe\u{301} ready hai, 🙏🏽 aaj", "ready hai, 🙏🏽"),
    ])
    func aQuoteThatIsPartOfALineIsMarkedWordForWord(chat: String, quote: String) {
        let words = String(chat.drop { $0 != ":" }.dropFirst(2))
        let fact = item(quote: quote, span: span(of: quote, in: words))
        let line = ProofEntry(ChatLine(id: 7, time: noon, text: chat, isCited: true), of: fact, self.words)
        #expect(marked(line) == [quote.nfc], "only the quote carries the stronger fill")
    }

    @Test func theQuoteIsNotMarkedWhenItIsTheWholeLineOrItsSpanDoesNotFitTheLine() {
        let words = "login API done"
        let whole = item(quote: words, span: span(of: words, in: words))
        func shown(_ fact: Item, id: Int64 = 7, cited: Bool = true, text: String = "Asha: login API done") -> [String] {
            marked(ProofEntry(ChatLine(id: id, time: noon, text: text, isCited: cited), of: fact, self.words))
        }
        let part = item(quote: "API", span: span(of: "API", in: words))
        #expect(shown(part) == ["API"], "a part is marked")
        #expect(shown(whole).isEmpty, "the whole line is already the cited line")
        #expect(shown(part, id: 8).isEmpty, "a span of another line marks nothing")
        #expect(shown(part, cited: false).isEmpty, "a line that is not cited marks nothing")
        #expect(shown(item(quote: "API", span: nil)).isEmpty, "no span, no mark")
        #expect(shown(item(quote: "API", span: QuoteSpan(line: 7, part: 0, start: 9, end: 99))).isEmpty)
        #expect(shown(item(quote: "API", span: QuoteSpan(line: 7, part: 1, start: 6, end: 9))).isEmpty)
        #expect(shown(item(source: .mail, quote: "API", span: span(of: "API", in: words))).isEmpty)
    }

    @Test func aLineShowsItsTimeItsSenderInSemiboldAndItsWords() {
        let line = ProofEntry(
            ChatLine(id: 7, time: noon, text: "Asha: login API done", isCited: true), of: item(), words)
        let text = line.text(scale: 1, quoteFill: .yellow)
        #expect(String(text.characters).contains(words.time(noon)))
        let sender = text.runs.first { String(text[$0.range].characters).hasPrefix("Asha") }
        #expect(sender?.font == Font.system(size: Font.TextStyle.callout.macSize, weight: .semibold))
        let plain = ProofEntry(
            ChatLine(id: 7, time: noon, text: "Asha: login API done", isCited: false), of: item(), words)
        #expect(plain.isCited == false && line.isCited)
    }

    @Test func theCitedLineShowsTheSameTimeAsTheSourceLineInAnyTimeZone() {
        var far = Calendar(identifier: .gregorian)
        far.timeZone = TimeZone(
            identifier: TimeZone.current.identifier == "America/Los_Angeles" ? "Asia/Tokyo" : "America/Los_Angeles")!
        let zoned = DateWords(now: noon, calendar: far, locale: Locale(identifier: "en_GB"))
        var fact = item()
        fact.start = noon
        let line = ProofEntry(ChatLine(id: 7, time: noon, text: "Asha: login API done", isCited: true), of: fact, zoned)
        let source = InspectorWords.source(of: fact, chat: nil, zoned)
        #expect(line.time.map { source.hasSuffix(", \($0)") } == true, "one fact shows two different times")
    }

    private let words = DateWords(
        now: Date(timeIntervalSince1970: 1_790_000_000), calendar: .current, locale: Locale(identifier: "en_GB"))

    @Test func historyIsPlainWordsOldestFirst() {
        let found = Date(timeIntervalSince1970: 1_789_900_000)
        let marked = DealStory.Marked(state: .confirmed, at: Date(timeIntervalSince1970: 1_789_950_000))
        var fact = item(dueDay: "2026-12-04")
        let history = ProofHistory(machine: "Pip", version: 3, found: found, marks: [marked])
        #expect(
            history.sentences(of: fact, words) == [
                "Found by Pip v3 on Sun 20 Sep.", "You marked it right on Mon.", "Due Fri 4 Dec.",
            ])
        fact.run = nil
        #expect(history.sentences(of: fact, words) == ["You marked it right on Mon.", "Due Fri 4 Dec."])
        #expect(
            ProofHistory(machine: nil, version: nil, found: nil).sentences(of: item(), words) == [
                "Found by a machine you removed."
            ])
    }

    @Test func aMarkThatWasTakenBackIsNotInTheHistoryAndAWrongMarkSaysWrong() {
        let at = Date(timeIntervalSince1970: 1_789_950_000)
        let back = [DealStory.Marked(state: .rejected, at: at), DealStory.Marked(state: .proposed, at: at)]
        #expect(!ProofHistory(marks: back).sentences(of: item(run: nil), words).contains { $0.hasPrefix("You marked") })
        let wrong = [DealStory.Marked(state: .confirmed, at: at), DealStory.Marked(state: .rejected, at: at)]
        #expect(ProofHistory(marks: wrong).sentences(of: item(run: nil), words) == ["You marked it wrong on Mon."])
        #expect(ProofHistory().sentences(of: item(run: nil), words).isEmpty, "nothing known, no history")
    }

    @Test func aDayOfTheLastWeekIsItsWeekdayAndAnOlderDayIsItsDate() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(words.recent(now.addingTimeInterval(-86_400)) == "Sun")
        #expect(words.recent(now.addingTimeInterval(-6 * 86_400)) == "Tue")
        #expect(words.recent(now.addingTimeInterval(-7 * 86_400)) == "Mon 14 Sep")
    }

    @Test func theSourceLineNamesTheSourceTheChatAndTheMoment() {
        let line = InspectorWords.source(of: item(), chat: "Founders group", words)
        #expect(line.hasPrefix("WhatsApp · Founders group · "))
        #expect(InspectorWords.source(of: item(source: .typed), chat: nil, words).hasPrefix("Typed by you · "))
        #expect(
            InspectorWords.meta(of: item(fields: ["person": "Asha", "project": "Login"], dueDay: "2026-12-04"), words)
                == "Login · due Fri 4 Dec")
    }

    @Test func theInspectorOffersDealsOnlyToATeamThatKeepsDeals() {
        #expect(InspectorMore.offersDeals(in: .fund))
        #expect(!InspectorMore.offersDeals(in: .startupTeam))
        #expect(!InspectorMore.offersDeals(in: .blank))
    }

    @Test func theSavedTeamTemplateDecidesWhetherTheInspectorOffersDeals() throws {
        let store = try scratchStore()
        let team = TeamModel(store: store, me: { "Kabir" })
        team.template = .fund
        team.save()
        #expect(InspectorMore.offersDeals(in: TeamModel(store: store, me: { "Kabir" }).template!))
        team.template = .startupTeam
        team.save()
        #expect(!InspectorMore.offersDeals(in: TeamModel(store: store, me: { "Kabir" }).template!))
    }

    @Test func theInspectorHeaderIsThePersonsQuoteAndTheMachinesTitleOnlyWithoutOne() async throws {
        let scene = try await read()
        let proof = ProofModel(
            crew: scene.crew, store: scene.store, title: { _ in "Machine title" }, lines: { _ in [] })
        let header = proof.card(for: scene.item).headline
        #expect(header.words == scene.item.quote && header.person == scene.item["person"])
        var bare = scene.item
        bare.quote = ""
        #expect(proof.card(for: bare).headline.words == "Machine title")
        #expect(!proof.card(for: scene.item).meta.contains(header.person), "the person is not said twice")
    }

    @Test func theProofPlaceholderHasOneRowForEachLineAFiveLineProofShows() {
        var fact = item(cite: 11)
        #expect(ProofModel.placeholderRows(for: fact) == 5)
        fact.citeLast = 12
        #expect(ProofModel.placeholderRows(for: fact) == 6)
        fact.citeLast = 400
        #expect(ProofModel.placeholderRows(for: fact) == ProofModel.mostRows)
    }

    @Test func citedTextAndTheQuoteFillStayReadableInLightAndDark() {
        for (name, scheme) in [(NSAppearance.Name.aqua, ColorScheme.light), (.darkAqua, .dark)] {
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                let page = rgb(Palette.page)
                let fill = mix(rgb(Palette.accent), over: page, ProofStyle.quoteOpacity(scheme))
                let tint = mix(rgb(Palette.accent), over: page, ProofStyle.citedOpacity(scheme))
                let text = rgb(Palette.text)
                #expect(contrast(text, fill) >= 4.5, "text on the quote fill, \(name.rawValue)")
                #expect(contrast(text, tint) >= 7, "text on the cited tint, \(name.rawValue)")
                #expect(contrast(rgb(Palette.text), page) >= 7)
            }
        }
    }
}

private func rgb(_ color: NSColor) -> [Double] {
    let c = color.usingColorSpace(.sRGB) ?? color
    return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
}

private func mix(_ top: [Double], over base: [Double], _ opacity: Double) -> [Double] {
    zip(top, base).map { $0 * opacity + $1 * (1 - opacity) }
}

private func contrast(_ a: [Double], _ b: [Double]) -> Double {
    func luminance(_ c: [Double]) -> Double {
        let l = c.map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
    }
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

private final class Counter { var count = 0 }

private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}
