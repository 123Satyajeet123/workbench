import Foundation
import Testing

@testable import WorkbenchCore

private let day = WorkDay(containing: t0)
private func at(_ minutes: Double) -> Date { day.start.addingTimeInterval(minutes * 60) }

/// Three messages of a team chat, with the members Asha and Bharat.
private let chat = EvidenceSet(
    lines: [
        Evidence(id: 10, start: at(900), line: "Kabir (founder): ki aaj kya kiya?", quotable: ["ki aaj kya kiya?"]),
        Evidence(
            id: 11, start: at(905), line: "Asha: login API done, kal payments",
            quotable: ["login API done, kal payments"]),
        Evidence(
            id: 13, start: at(960), line: "Asha: \u{0915}\u{093C}\u{0932}  tak deploy",
            quotable: ["\u{0915}\u{093C}\u{0932}  tak deploy"]),
    ], context: ["members": ["Asha", "Bharat"]])

/// Four screen sessions of an hour and a half.
private let screen = EvidenceSet(lines: [
    Evidence(id: 1, start: at(0), end: at(40), line: "Terminal — app — claude", quotable: ["app — claude", ""]),
    Evidence(
        id: 2, start: at(40), end: at(70), line: "Brave — PR · login API",
        quotable: ["PR · login API", "github.com/x/12"]),
    Evidence(id: 3, start: at(70), end: at(90), line: "WhatsApp — Technical Staff", quotable: ["Technical Staff", ""]),
    Evidence(id: 4, start: at(90), end: at(100), line: "Brave — YouTube", quotable: ["YouTube", "youtube.com"]),
])

private func entry(_ person: String, _ kind: String = "done", cite: Int, quote: String, text: String = "t") -> String {
    #"{"person":"\#(person)","kind":"\#(kind)","text":"\#(text)","eta":"","cite":\#(cite),"quote":"\#(quote)"}"#
}

private func block(_ first: Int, _ last: Int, task: String = "Work", quote: String) -> String {
    #"{"task":"\#(task)","project":"","first":\#(first),"last":\#(last),"quote":"\#(quote)"}"#
}

private func read(
    _ spec: HelperSpec, _ items: [String], evidence: EvidenceSet, store: Store? = nil
) async throws -> (HelperReader.Result, ScriptedModel) {
    let model = ScriptedModel(#"{"items":[\#(items.joined(separator: ","))]}"#)
    let reader = HelperReader(spec: spec, model: RecordedModel(model, store: try store ?? makeStore()))
    return (try await reader.read(day: day, scope: "team", evidence: evidence), model)
}

@Suite struct HelperReaderTests {
    @Test func anItemIsKeptWhenItsQuoteIsInTheLineItCitesAndDroppedWhenItIsNot() async throws {
        let (result, _) = try await read(
            .team, [entry("Asha", cite: 11, quote: "login API done"), entry("Asha", cite: 11, quote: "payments done")],
            evidence: chat)
        #expect(result.items.map(\.quote) == ["login API done"])
        #expect(result.dropped == 1)
        #expect(result.items.first?.start == at(905))
        #expect(result.items.first?.run == result.run)
    }

    @Test func aQuoteFromAnotherLineOrAnUnknownLineIsDropped() async throws {
        let (result, _) = try await read(
            .team, [entry("Asha", cite: 10, quote: "login API done"), entry("Asha", cite: 99, quote: "login")],
            evidence: chat)
        #expect(result.items.isEmpty && result.dropped == 2)
    }

    @Test func aQuoteMatchesAcrossSpellingFormCaseAndSpacingButNotOtherWords() async throws {
        let (kept, _) = try await read(
            .team, [entry("Asha", cite: 13, quote: "\u{0958}\u{0932} TAK deploy")], evidence: chat)
        #expect(kept.items.count == 1)
        let (dropped, _) = try await read(
            .team, [entry("Asha", cite: 13, quote: "\u{0958}\u{0932} tak release")], evidence: chat)
        #expect(dropped.items.isEmpty)
    }

    @Test func fieldsMustFitTheirKinds() async throws {
        let (result, _) = try await read(
            .team,
            [
                entry("Asha", cite: 11, quote: "login"), entry("Rahul", cite: 11, quote: "login"),
                entry("Asha", "maybe", cite: 11, quote: "login"), entry("Asha", cite: 11, quote: "login", text: " "),
            ], evidence: chat)
        #expect(result.items.count == 1)
        #expect(result.dropped == 3)
    }

    @Test func aRangeIsKeptWhenTheQuoteIsInsideItAndOverlapsReversedOrUnknownRangesAreDropped() async throws {
        let (result, _) = try await read(
            .timeline,
            [
                block(1, 2, quote: "login API"), block(2, 3, quote: "Technical Staff"), block(3, 3, quote: "login API"),
                block(4, 3, quote: "YouTube"), block(4, 9, quote: "YouTube"), block(4, 4, quote: "youtube.com"),
            ], evidence: screen)
        #expect(result.items.map { [$0.citeFirst, $0.citeLast] } == [[1, 2], [4, 4]])
        #expect(result.items.first?.start == at(0) && result.items.first?.end == at(70))
        #expect(result.dropped == 4)
    }

    @Test func aDayWithNoEvidenceRunsNoModel() async throws {
        let store = try makeStore()
        let (result, model) = try await read(.team, [], evidence: EvidenceSet(lines: []), store: store)
        #expect(result == HelperReader.Result(items: [], dropped: 0, run: nil))
        #expect(model.inputs.withLock { $0.isEmpty })
        #expect(try store.queries.runs().isEmpty)
    }

    @Test func theModelSeesTheBriefTheRulesTheContextAndNumberedLines() async throws {
        let (_, model) = try await read(.team, [], evidence: chat)
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("Members: Asha, Bharat"))
        #expect(input.contains("[11] "))
        #expect(input.contains("Asha: login API done, kal payments"))
        let reader = HelperReader(spec: .team, model: RecordedModel(model, store: try makeStore()))
        #expect(reader.instructions.hasPrefix(HelperSpec.team.brief))
        #expect(reader.instructions.contains("- person: exactly one name from the members list."))
        #expect(reader.instructions.contains("- cite: the number of the line it comes from."))
        let timeline = HelperReader(spec: .timeline, model: RecordedModel(model, store: try makeStore()))
        #expect(timeline.instructions.contains("- first, last:"))
        #expect(try timeline.schema.jsonText.contains(#""last""#))
    }
}

@Suite struct ItemStoreTests {
    private let chatGrant = grant(.whatsapp, label: "team")

    private func save(_ items: [String], _ spec: HelperSpec = .team, into store: Store) async throws {
        let (result, _) = try await read(spec, items, evidence: spec == .team ? chat : screen, store: store)
        try store.saveReading(
            result, of: spec, day: day, scope: spec == .team ? "team" : "",
            grant: spec == .team ? chatGrant : grant(.screen))
    }

    private func items(_ store: Store, _ spec: HelperSpec = .team) throws -> [Item] {
        try store.queries.items(of: spec.task, day: day, scope: spec == .team ? "team" : "")
    }

    @Test func aNewReadingReplacesWhatIsUnmarkedKeepsWhatIsMarkedAndDoesNotRepeatIt() async throws {
        let store = try makeStore()
        try await save(
            [entry("Asha", cite: 11, quote: "login"), entry("Asha", cite: 11, quote: "payments")], into: store)
        let first = try items(store)
        try store.mark(item: try #require(first[0].id), as: .rejected)
        try await save(
            [entry("Asha", cite: 11, quote: "login"), entry("Asha", cite: 11, quote: "API done")], into: store)
        let now = try items(store)
        #expect(now.map(\.quote).sorted() == ["API done", "login"])
        #expect(now.first { $0.quote == "login" }?.state == .rejected)
    }

    @Test func aRangeThatOverlapsAMarkedBlockIsNotAddedAgain() async throws {
        let store = try makeStore()
        try await save([block(1, 2, quote: "login API")], .timeline, into: store)
        try store.mark(item: try #require(items(store, .timeline).first?.id), as: .confirmed)
        try await save([block(2, 3, quote: "Technical Staff"), block(4, 4, quote: "YouTube")], .timeline, into: store)
        #expect(try items(store, .timeline).map(\.citeFirst) == [1, 4])
    }

    @Test func marksAreHistoryAndTheLatestIsTheState() async throws {
        let store = try makeStore()
        try await save([entry("Asha", cite: 11, quote: "login")], into: store)
        let id = try #require(items(store).first?.id)
        try store.mark(item: id, as: .confirmed)
        try store.mark(item: id, as: .proposed)
        #expect(try items(store).first?.state == .proposed)
        #expect(try store.queries.count(of: .mark) == 2)
    }

    @Test func aGrantForAnotherChatAnotherSourceOrAnExpiredGrantWritesNothing() async throws {
        let store = try makeStore()
        let (result, _) = try await read(.team, [entry("Asha", cite: 11, quote: "login")], evidence: chat, store: store)
        for wrong in [
            grant(.whatsapp, label: "family"), grant(.screen), grant(.whatsapp, label: "team", at: day.start),
        ] {
            #expect(throws: StoreError.self) {
                try store.saveReading(result, of: .team, day: day, scope: "team", grant: wrong)
            }
        }
        #expect(try items(store).isEmpty)
        try store.saveReading(result, of: .team, day: day, scope: "team", grant: chatGrant)
        #expect(try items(store).count == 1)
    }

    @Test func marksGivePrecisionPerTaskModelAndPrompt() async throws {
        let store = try makeStore()
        try await save(
            [
                entry("Asha", cite: 11, quote: "login"), entry("Asha", cite: 11, quote: "API"),
                entry("Asha", cite: 11, quote: "done"), entry("Asha", cite: 11, quote: "invented"),
            ], into: store)
        let saved = try items(store)
        try store.mark(item: try #require(saved[0].id), as: .confirmed)
        try store.mark(item: try #require(saved[1].id), as: .confirmed)
        try store.mark(item: try #require(saved[2].id), as: .rejected)
        let quality = try #require(store.queries.quality().first)
        #expect(quality.task == HelperSpec.team.task)
        #expect((quality.runs, quality.kept, quality.dropped) == (1, 3, 1))
        #expect(quality.all == Tally(confirmed: 2, rejected: 1))
        #expect(quality.version == 1)
    }

    @Test func deletingASourceRemovesItsItemsAndTheirMarksButNotOtherSources() async throws {
        let store = try makeStore()
        try await save([entry("Asha", cite: 11, quote: "login")], into: store)
        try await save([block(1, 2, quote: "login API")], .timeline, into: store)
        try store.mark(item: try #require(items(store).first?.id), as: .confirmed)
        try store.delete(.kind(.whatsapp, before: nil))
        #expect(try items(store).isEmpty)
        #expect(try store.queries.count(of: .mark) == 0)
        #expect(try items(store, .timeline).count == 1)
        #expect(try store.queries.runs().count == 2)
    }

    @Test func forgettingActivityRemovesOnlyTheScreenItemsOverItsTime() async throws {
        let store = try makeStore(clock: { at(5) })
        var engine = CaptureEngine()
        let snapshot = ScreenSnapshot(app: "Brave", bundleID: "b", windowID: 1, title: "Docs", text: "")
        let batch = engine.observe(
            snapshot, idleSeconds: 0, policy: CapturePolicy(switches: [.screen: true]), at: at(5))
        try store.record(#require(batch))
        try await save(
            [block(1, 1, quote: "app — claude"), block(3, 3, quote: "Technical Staff")], .timeline, into: store)
        try await save([entry("Asha", cite: 11, quote: "login")], into: store)
        let row = try #require(store.queries.activities(since: .distantPast).first?.id)
        try store.delete(.activities(ActivityFilter(id: row)))
        #expect(try items(store, .timeline).map(\.citeFirst) == [3])
        #expect(try items(store).count == 1)
    }

    private func readAndSave(_ items: [String], into store: Store, pick: Int) async throws {
        let (result, _) = try await read(.team, items, evidence: chat, store: store)
        try store.saveReading(result, of: .team, day: day, scope: "team", grant: chatGrant, pick: { _ in pick })
    }

    @Test func aReadingPicksOneOfItsNewItemsToAskAboutAndKeepsItsChance() async throws {
        let store = try makeStore()
        try await readAndSave(
            ["login", "API", "done"].map { entry("Asha", cite: 11, quote: $0) }, into: store, pick: 1)
        let saved = try items(store)
        #expect(saved.map(\.askedWith) == [nil, 1.0 / 3, nil])
        try await readAndSave([], into: store, pick: 0)
        #expect(try items(store).allSatisfy { $0.askedWith == nil })
    }

    @Test func aMarkOnAPickedItemIsAnAuditMarkAndAnyOtherMarkIsVoluntary() async throws {
        let store = try makeStore()
        try await readAndSave(["login", "API"].map { entry("Asha", cite: 11, quote: $0) }, into: store, pick: 0)
        let saved = try items(store)
        try store.mark(item: try #require(saved[0].id), as: .confirmed)
        try store.mark(item: try #require(saved[1].id), as: .rejected)
        let marks = try store.database.rows("SELECT origin, asked_with FROM mark ORDER BY id")
        #expect(marks.map { $0[0].string } == ["audit", "voluntary"])
        #expect(marks.map { $0[1].double } == [0.5, 1])
    }

    @Test func theAuditEstimateWeighsEachAnswerByOneOverItsChanceAndIgnoresVoluntaryMarks() async throws {
        let store = try makeStore()
        try await readAndSave(
            ["login", "API", "done", "kal"].map { entry("Asha", cite: 11, quote: $0) }, into: store, pick: 0)
        let first = try items(store)
        try store.mark(item: try #require(first[0].id), as: .confirmed)
        try store.mark(item: try #require(first[1].id), as: .rejected)
        try await readAndSave([entry("Asha", cite: 11, quote: "payments")], into: store, pick: 0)
        try store.mark(item: try #require(items(store).first { $0.quote == "payments" }?.id), as: .rejected)
        let quality = try #require(store.queries.quality().first)
        #expect(quality.audited == AuditEstimate(marks: 2, rightWeight: 4, weight: 5))
        #expect(quality.audited.precision == 0.8)
        #expect(quality.all == Tally(confirmed: 1, rejected: 2))
    }

    @Test func theSchemaRefusesAnEmptyQuoteAFieldThatIsNotAnObjectAndAnItemWithoutARun() throws {
        let store = try makeStore()
        let insert = """
            INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields, quote,
                created_at) VALUES ('t', ?, 'd', '', 'screen', 1, 1, 'a', 'a', ?, ?, 'now')
            """
        let run = try store.beginRun(task: "t", model: "m", prompt: "p", input: "x")
        #expect(throws: (any Error).self) { try store.database.run(insert, [.int(run), .text("{}"), .text("")]) }
        #expect(throws: (any Error).self) { try store.database.run(insert, [.int(run), .text("[]"), .text("q")]) }
        #expect(throws: (any Error).self) { try store.database.run(insert, [.int(999), .text("{}"), .text("q")]) }
        try store.database.run(insert, [.int(run), .text("{}"), .text("q")])
    }
}
