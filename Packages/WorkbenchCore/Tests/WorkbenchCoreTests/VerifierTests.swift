import Foundation
import Kernel
import Testing

@testable import WorkbenchCore

private let day = WorkDay(containing: t0)

private func source(_ key: String) throws -> SourceID { try Source(owner: PersonID("me"), key: SourceKey(key)).id }

private func provenance(_ key: String, _ authority: Authority) throws -> Provenance {
    Provenance(label: Label(source: try source(key)), authority: authority)
}

private func line(_ id: Int64, _ text: String, provenance: Provenance? = nil) -> Evidence {
    Evidence(id: id, start: t0, line: text, quotable: [text], provenance: provenance)
}

private func raw(_ json: String) throws -> [String: WorkbenchCore.JSONValue] {
    try JSONDecoder().decode([String: WorkbenchCore.JSONValue].self, from: Data(json.utf8))
}

private func proposal(
    cite: Int, quote: String, kind: String = "done", person: String = "Asha", when: String = TimeJSON.none,
    extra: String = ""
) -> String {
    #"{"person":"\#(person)","project":"Login","kind":"\#(kind)","text":"t","when":\#(when),"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":\#(cite),"quote":"\#(quote)"\#(extra)}"#
}

private func verifier(_ lines: [Evidence], settings: Verifier.Settings = Verifier.Settings(), read: Set<Int64> = [])
    -> Verifier
{
    Verifier(
        window: EvidenceSet(lines: lines, context: ["members": ["Asha"]], read: read), settings: settings)
}

private func judge(_ json: String, in verifier: Verifier, spec: HelperSpec = .team) throws -> Judgment<Item> {
    let item = try raw(json)
    return verifier.verdict {
        try verifier.item(item, spec: spec, open: [], day: day, scope: "", run: 1)
    }
}

private func dropRule<Value>(_ judgment: Judgment<Value>) -> DropRule? {
    if case .dropped(let rule) = judgment { rule } else { nil }
}

@Suite struct QuoteFoldTests {
    @Test func aTrueQuoteWithACurlyApostropheOrQuotationMarkPassesInBothDirections() {
        #expect("Rahul: I\u{2019}ll send the deck kal".contains(quote: "I'll send the deck"))
        #expect("Rahul: I'll send the deck kal".contains(quote: "I\u{2019}ll send the deck"))
        #expect("He said \u{201C}done\u{201D} today".contains(quote: "said \"done\" today"))
        #expect("He said \"done\" today".contains(quote: "said \u{201C}done\u{201D} today"))
    }

    @Test func aDandaIsAFullStopAndZeroWidthCharactersAreNotThere() {
        #expect("kal tak bhej dunga\u{0964} ok".contains(quote: "bhej dunga. ok"))
        #expect("deck bhej dunga.".contains(quote: "bhej dunga\u{0964}"))
        #expect("de\u{200B}ck do\u{200D}ne".contains(quote: "deck done"))
        #expect("deck done".contains(quote: "de\u{200C}ck\u{FEFF} done"))
    }

    @Test func caseWhiteSpaceAndSpellingFormAreFolded() {
        #expect("Login   API\n done".contains(quote: "login api done"))
        #expect("\u{0915}\u{093C}\u{0932}".contains(quote: "\u{0958}\u{0932}"), "a nukta letter in two spellings")
    }

    @Test func aQuoteIsFoundExactlyOrNotAtAll() {
        let text = "I will send the deck to Rahul tomorrow"
        #expect(!text.contains(quote: "I will send a deck to Rahul"), "one word changed")
        #expect(!text.contains(quote: "I will send the deck to Rohan tomorrow"), "one name changed")
        #expect(!text.contains(quote: "send deck the"), "the words in another order")
        #expect(!"bhej dunga".contains(quote: "bhejunga"), "a transliteration is not the text")
        #expect(!text.contains(quote: ""))
        #expect(!text.contains(quote: " \u{200B} "))
    }

    @Test func aMatchGivesItsOffsetsInTheNormalFormCText() {
        #expect("Asha: I\u{2019}ll send the deck".span(of: "i'll   SEND") == 6..<15)
        #expect("ok  deal  done".span(of: "deal done") == 4..<14)
        #expect("a\u{200B}b cd".span(of: "b c") == 2..<5)
        #expect("deck".span(of: "deck deck") == nil)
    }
}

@Suite struct VerifierTests {
    @Test func aTrueQuoteWithACurlyApostropheIsKeptAndItsOffsetsAreKept() throws {
        let lines = [line(10, "Asha: I\u{2019}ll send the deck")]
        let kept = try #require(
            try judge(proposal(cite: 10, quote: "I'll send the deck"), in: verifier(lines)).accepted)
        #expect(kept.quoteSpan == QuoteSpan(line: 10, part: 0, start: 6, end: 24))
    }

    @Test func aQuoteThatIsNotInTheCitedLinesFails() throws {
        let lines = [line(10, "Asha: login done"), line(11, "Asha: deck sent")]
        let there = verifier(lines)
        #expect(try judge(proposal(cite: 10, quote: "login done"), in: there).accepted != nil)
        #expect(dropRule(try judge(proposal(cite: 10, quote: "deck sent"), in: there)) == .quoteNotInLines)
        #expect(dropRule(try judge(proposal(cite: 10, quote: "login finished"), in: there)) == .quoteNotInLines)
    }

    @Test func aLineOutsideTheWindowOrAlreadyReadCannotBeCited() throws {
        let lines = [line(10, "Asha: login done"), line(11, "Asha: deck sent")]
        let there = verifier(lines, read: [10])
        #expect(dropRule(try judge(proposal(cite: 99, quote: "login done"), in: there)) == .outsideWindow)
        #expect(dropRule(try judge(proposal(cite: 10, quote: "login done"), in: there)) == .outsideWindow)
        #expect(try judge(proposal(cite: 11, quote: "deck sent"), in: there).accepted != nil)
    }

    @Test func aMissingKeyIsMalformed() throws {
        #expect(dropRule(try judge(#"{"quote":"x"}"#, in: verifier([line(10, "x")]))) == .malformed)
    }

    @Test func fieldsMustBeOfTheirKinds() throws {
        let there = verifier([line(10, "Asha: login done")])
        #expect(dropRule(try judge(proposal(cite: 10, quote: "login", kind: "maybe"), in: there)) == .fieldKind)
        #expect(dropRule(try judge(proposal(cite: 10, quote: "login", person: "Rahul"), in: there)) == .fieldKind)
        #expect(try judge(proposal(cite: 10, quote: "login", kind: "blocker"), in: there).accepted != nil)
    }

    @Test func aDateFieldTakesAWorkDayOrNothing() throws {
        var spec = HelperSpec.team
        spec.fields.append(.init("by", .date(required: false), meaning: "m"))
        let there = verifier([line(10, "Asha: login done")])
        func by(_ value: String) throws -> Judgment<Item> {
            try judge(proposal(cite: 10, quote: "login", extra: #","by":"\#(value)""#), in: there, spec: spec)
        }
        #expect(try by("2026-11-24").accepted != nil)
        #expect(try by("").accepted != nil)
        #expect(dropRule(try by("kal")) == .fieldKind)
        #expect(dropRule(try by("2026-13-45")) == .fieldKind)
        spec.fields[spec.fields.count - 1] = .init("by", .date(required: true), meaning: "m")
        #expect(dropRule(try by("")) == .fieldKind)
    }

    // MARK: the time field

    private func timed(_ when: String, said text: String = "Asha: login done kal tak") throws -> Judgment<Item> {
        try judge(
            proposal(cite: 10, quote: "login", when: when),
            in: Verifier(
                window: EvidenceSet(lines: [line(10, text)], context: ["members": ["Asha"]]),
                zone: TimeZone(identifier: "Asia/Kolkata")!))
    }

    @Test func aTimeFieldKeepsTheWordsAndTheDueTimeCodeResolvedFromTheLinesOwnTime() throws {
        let kept = try #require(try timed(TimeJSON.inDays(1, words: "kal tak")).accepted)
        #expect(kept["when"] == "kal tak")
        let due = try #require(kept.openedDue)
        #expect(due.source == .resolved && due.zone == "Asia/Kolkata" && due.precision == .day)
        let calendar = Calendar.gregorian(in: TimeZone(identifier: "Asia/Kolkata")!)
        #expect(due.utc == calendar.endOfDay(of: calendar.date(byAdding: .day, value: 1, to: t0)!))
        #expect(due.record?.offsetDays == 1)
    }

    @Test func aTimeFieldWithNoTimeKeepsNoWordsAndNoDueTime() throws {
        let kept = try #require(try timed(TimeJSON.none).accepted)
        #expect(kept["when"] == "" && kept.openedDue?.source == Due.Source.none && kept.dueDay == nil)
    }

    @Test func anAmbiguousOrPastRecordIsKeptWithItsRecordAndGivesNoDueTime() throws {
        let ambiguous = TimeJSON.record(
            "future", offset: 1, precision: "day", ambiguous: true, words: "kal tak")
        let past = TimeJSON.record("past", offset: -1, precision: "day", words: "kal")
        for when in [ambiguous, past] {
            let kept = try #require(try timed(when).accepted)
            #expect(kept.openedDue?.source == Due.Source.none && kept.openedDue?.utc == nil && kept.dueDay == nil)
            #expect(kept.openedDue?.record != nil && kept["when"] != "")
        }
    }

    @Test func aTimeRecordThatIsNotTheClosedRecordIsDropped() throws {
        let dropped = [
            #"{"direction":"future","offset_days":1}"#,
            #"{"direction":"tomorrow","offset_days":1,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"day","ambiguous":false,"words":"kal"}"#,
            #"{"direction":"future","offset_days":1.5,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"day","ambiguous":false,"words":"kal"}"#,
            TimeJSON.record("future", offset: 400, precision: "day", words: "kal"),
            TimeJSON.record("future", offset: -1, precision: "day", words: "kal"),
            TimeJSON.record("future", weekday: "friday", precision: "day", words: "kal"),
            TimeJSON.record("future", offset: 1, precision: "day", words: ""),
            TimeJSON.record("future", precision: "hour", words: "kal", hour: 17, meridiem: "pm"),
            TimeJSON.record("future", part: "evening", precision: "hour", words: "kal", hour: 5, meridiem: "am"),
            TimeJSON.record("future", precision: "day", words: "kal", dayOfMonth: 30),
            TimeJSON.record("future", precision: "hour", words: "kal", minutes: 90),
            TimeJSON.record("future", precision: "month", words: "kal", month: 3, monthWhich: "this"),
            #""2026-11-24""#,
        ]
        for when in dropped { #expect(dropRule(try timed(when)) == .fieldKind, "\(when)") }
    }

    @Test func aClockTimeADateAndAMonthResolveThroughTheVerifierAndAnHourWithNoMeridiemGivesNoDueTime() throws {
        let kolkata = Calendar.gregorian(in: TimeZone(identifier: "Asia/Kolkata")!)
        let tomorrow = kolkata.date(byAdding: .day, value: 1, to: kolkata.startOfDay(for: t0))!
        let evening = TimeJSON.record(
            "future", offset: 1, part: "evening", precision: "hour", words: "kal tak", hour: 5)
        let kept = try #require(try timed(evening).accepted)
        #expect(kept.openedDue?.utc == kolkata.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow))
        let bare = TimeJSON.record("future", offset: 1, precision: "hour", words: "kal tak", hour: 5)
        let unknown = try #require(try timed(bare).accepted)
        #expect(unknown.openedDue?.source == Due.Source.none && unknown.openedDue?.record != nil)
        let dec = TimeJSON.record("future", precision: "day", words: "kal tak", dayOfMonth: 31, month: 4, year: 2027)
        #expect(try timed(dec).accepted?.openedDue?.source == Due.Source.none, "April has 30 days: no due time")
    }

    @Test func theWordsOfATimeMustBeInTheCitedLine() throws {
        let said = TimeJSON.inDays(1, words: "kal tak")
        #expect(try timed(said).accepted != nil)
        #expect(dropRule(try timed(said, said: "Asha: login done parson tak")) == .quoteNotInLines)
        #expect(try timed(TimeJSON.inDays(1, words: "KAL  tak"), said: "Asha: login done kal tak").accepted != nil)
    }

    @Test func aCheckThatFailsDropsTheProposalWithAReason() {
        struct Broken: Error {}
        let there = verifier([])
        let failed: Judgment<Int> = there.verdict { throw Broken() }
        let refused: Judgment<Int> = there.verdict { throw Refusal(.unknownHandle) }
        let passed: Judgment<Int> = there.verdict { 7 }
        #expect(dropRule(failed) == .verifierError)
        #expect(dropRule(refused) == .unknownHandle)
        #expect(passed.accepted == 7)
    }

    @Test func theMinimumQuoteStrengthIsOffUnlessSetAndAWholeLineIsExempt() throws {
        let lines = [line(10, "Asha: login done"), line(11, "ok")]
        let off = verifier(lines)
        let on = verifier(lines, settings: Verifier.Settings(minimumQuoteWords: 3))
        #expect(Verifier.Settings().minimumQuoteWords == nil)
        #expect(try judge(proposal(cite: 10, quote: "a"), in: off).accepted != nil, "off: a one-letter quote passes")
        #expect(dropRule(try judge(proposal(cite: 10, quote: "a"), in: on)) == .quoteTooShort)
        #expect(dropRule(try judge(proposal(cite: 10, quote: "login done"), in: on)) == .quoteTooShort)
        #expect(try judge(proposal(cite: 10, quote: "Asha: login done"), in: on).accepted != nil, "three words")
        #expect(try judge(proposal(cite: 11, quote: "ok"), in: on).accepted != nil, "the whole line")
    }

    @Test func theModelCannotSetALabelOrAnAuthority() throws {
        let lines = [line(10, "Asha: login done", provenance: try provenance("wa:team", .groupMember))]
        let forged = proposal(cite: 10, quote: "login", extra: #","label":"public","authority":"own_words""#)
        let kept = try #require(try judge(forged, in: verifier(lines)).accepted)
        #expect(kept.label == Label(source: try source("wa:team")))
        #expect(kept.authority == .groupMember)
    }

    @Test func aReadingKeepsTheFirstOfTwoProposalsThatSayTheSameAndDropsTheRest() throws {
        let there = verifier([])
        let result = try there.settle(
            [1, 2, 2, 3], part: "items",
            check: { (value: Int) throws -> Int in if value > 2 { throw Refusal(.malformed) } else { return value } },
            isRepeat: { value, kept in kept.contains(value) })
        #expect(result.kept == [1, 2])
        #expect(result.drops.map(\.rule) == [.repeatInReading, .malformed])
        #expect(result.drops.map(\.ordinal) == [2, 3])
    }
}

@Suite struct StandingTests {
    @Test func aFactIsLabelledWithTheJoinOfItsCitedLinesAndNoNarrower() throws {
        let team = try provenance("wa:team", .ownWords)
        let other = try provenance("wa:other", .ownWords)
        let both = Standing(
            citing: [line(1, "a", provenance: team), line(2, "b", provenance: other)], facts: [], window: [])
        #expect(both.label == Label(source: try source("wa:team")).joined(with: Label(source: try source("wa:other"))))
        let one = Standing(citing: [line(1, "a", provenance: team)], facts: [], window: [])
        #expect(one.label == team.label, "one source keeps its label")
    }

    @Test func aFactIsLabelledWithTheJoinOfItsWholeWindowNotOnlyItsCitedLines() throws {
        let team = try provenance("wa:team", .ownWords)
        let restricted = try provenance("wa:private", .ownWords)
        let cited = line(1, "a", provenance: team)
        let uncited = line(2, "b", provenance: restricted)
        let wide = Standing(citing: [cited], facts: [], window: [cited, uncited])
        #expect(wide.label == team.label.joined(with: restricted.label), "an uncited line of another label counts")
        let same = Standing(citing: [cited], facts: [], window: [cited, line(3, "c", provenance: team)])
        #expect(same.label == team.label, "one label in the window gives that label")
        #expect(Standing(citing: [cited], facts: [], window: [cited, line(4, "d")]).label == nil, "an unknown line")
    }

    @Test func aLineOrFactWithNoKnownLabelLeavesNoLabel() throws {
        let team = try provenance("wa:team", .ownWords)
        #expect(Standing(citing: [line(1, "a", provenance: team), line(2, "b")], facts: [], window: []).label == nil)
        let unlabelled = Item(
            task: "t", day: day, scope: "", source: .whatsapp, citeFirst: 1, citeLast: 1, start: t0, end: t0,
            fields: [:], quote: "q", run: 1)
        #expect(Standing(citing: [line(1, "a", provenance: team)], facts: [unlabelled], window: []).label == nil)
    }

    @Test func authorityIsTheLeastOfTheCitedLinesTheFactsAndTheWindow() throws {
        let own = try provenance("wa:a", .ownWords)
        let member = try provenance("wa:a", .groupMember)
        let forwarded = try provenance("wa:a", .forwardedOrQuoted)
        let ownLine = line(1, "a", provenance: own)
        #expect(Standing(citing: [ownLine], facts: [], window: [ownLine]).authority == .ownWords)
        #expect(
            Standing(citing: [ownLine, line(2, "b", provenance: member)], facts: [], window: []).authority
                == .groupMember)
        #expect(
            Standing(citing: [ownLine, line(3, "c", provenance: forwarded)], facts: [], window: []).authority
                == .forwardedOrQuoted)
        #expect(
            Standing(citing: [ownLine], facts: [], window: [ownLine, line(4, "d", provenance: forwarded)]).authority
                == .forwardedOrQuoted, "a weak line of the window lowers it")
        #expect(Standing(citing: [ownLine, line(5, "e")], facts: [], window: []).authority == .unknown)
        var weak = Item(
            task: "t", day: day, scope: "", source: .whatsapp, citeFirst: 1, citeLast: 1, start: t0, end: t0,
            fields: [:], quote: "q", run: 1)
        weak.authority = .groupMember
        #expect(Standing(citing: [ownLine], facts: [weak], window: []).authority == .groupMember, "a fact it cites")
    }

    @Test func authorityComesFromTheSenderTheSourceRecorded() {
        #expect(Authority(actor: "me", owner: "me") == .ownWords)
        #expect(Authority(actor: "91@s.whatsapp.net", owner: "me") == .groupMember)
        #expect(Authority(actor: nil, owner: "me") == .unknown)
        #expect(Authority.unknown < .forwardedOrQuoted && Authority.forwardedOrQuoted < .groupMember)
        #expect(Authority.groupMember < .ownWords)
    }
}

extension Judgment {
    fileprivate var accepted: Value? { if case .accepted(let value) = self { value } else { nil } }
}
