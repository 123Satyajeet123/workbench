import Foundation
import GRDB
import Kernel
import Testing

@testable import WorkbenchCore

/// M2 step 1: a reading goes through the one verifier, every proposal it refuses leaves a drop-reason row, and a fact
/// keeps the offsets of its quote, its label and its authority.
@Suite struct GroundedFactsTests {
    private let day = WorkDay(containing: t0)
    private let teamGrant = grant(.whatsapp, label: "team")

    private func provenance(_ key: String, _ authority: Authority) throws -> Provenance {
        Provenance(
            label: Label(source: try Source(owner: PersonID("me"), key: SourceKey(key)).id), authority: authority)
    }

    private func chat() throws -> EvidenceSet {
        EvidenceSet(
            lines: [
                Evidence(
                    id: 10, start: t0, line: "Asha: I\u{2019}ll send the deck kal",
                    quotable: ["I\u{2019}ll send the deck kal"],
                    provenance: try provenance("wa:team", .groupMember)),
                Evidence(
                    id: 11, start: t0, line: "Kabir: ok, send it", quotable: ["ok, send it"],
                    provenance: try provenance("wa:team", .ownWords)),
            ], context: ["members": ["Asha", "Bharat"]])
    }

    private func item(cite: Int, quote: String, person: String = "Asha") -> String {
        #"{"person":"\#(person)","project":"Login","kind":"commitment","text":"t","eta":"","asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":\#(cite),"quote":"\#(quote)"}"#
    }

    private func read(_ items: [String], store: Store) async throws -> HelperReader.Result {
        let model = ScriptedModel(#"{"items":[\#(items.joined(separator: ","))]}"#)
        return try await HelperReader(spec: .team, model: RecordedModel(model, store: store))
            .read(day: day, scope: "team", evidence: try chat())
    }

    @Test func aTrueQuoteWithACurlyApostropheIsKeptAndItsOffsetsAndStandingAreStored() async throws {
        let store = try makeStore()
        let result = try await read([item(cite: 10, quote: "I'll send the deck")], store: store)
        #expect(result.dropped == 0)
        try store.saveReading(result, of: .team, day: day, scope: "team", grant: teamGrant)
        let saved = try #require(try store.queries.items(of: HelperSpec.team.task, day: day, scope: "team").first)
        #expect(saved.quoteSpan == QuoteSpan(line: 10, part: 0, start: 0, end: 18))
        #expect(saved.label == (try provenance("wa:team", .ownWords)).label)
        #expect(saved.authority == .groupMember)
    }

    @Test func aFactTakesTheLeastAuthorityOfTheWindowAndTheJoinOfTheLabelsItCites() async throws {
        let store = try makeStore()
        let result = try await read([item(cite: 11, quote: "send it")], store: store)
        let kept = try #require(result.items.first)
        #expect(kept.authority == .groupMember, "it cites the owner's line, and the window holds a member's line")
        #expect(kept.label == (try provenance("wa:team", .ownWords)).label)
    }

    @Test func everyDropLeavesOneRowWithItsRuleAndAKeptItemLeavesNone() async throws {
        let store = try makeStore()
        let result = try await read(
            [
                item(cite: 10, quote: "send the deck"), item(cite: 10, quote: "send a deck"),
                item(cite: 10, quote: "send the deck", person: "Rahul"), item(cite: 99, quote: "x"),
            ], store: store)
        #expect(result.items.count == 1 && result.dropped == 3)
        let rows = try store.queries.dropReasons(of: try #require(result.run))
        #expect(rows.map(\.rule) == [.quoteNotInLines, .fieldKind, .outsideWindow])
        #expect(rows.map(\.ordinal) == [1, 2, 3])
        #expect(rows.allSatisfy { $0.part == "items" } && rows.first?.proposal.contains("send a deck") == true)
    }

    @Test func aReadingWithNoDropLeavesNoRow() async throws {
        let store = try makeStore()
        let result = try await read([item(cite: 10, quote: "send the deck")], store: store)
        #expect(try store.queries.dropReasons(of: try #require(result.run)).isEmpty)
    }

    @Test func dropRowsGoWithTheRunTextWhenASourceIsDeletedAndTheRunRowStays() async throws {
        let store = try makeStore()
        let result = try await read([item(cite: 10, quote: "send a deck")], store: store)
        let run = try #require(result.run)
        #expect(try store.queries.dropReasons(of: run).count == 1)
        try store.delete(.kind(.whatsapp, before: nil))
        #expect(try store.queries.dropReasons(of: run).isEmpty)
        #expect(try store.queries.runs().map(\.id) == [run])
    }

    @Test func dropRowsAreWrittenOnceAndNeverChange() async throws {
        let store = try makeStore()
        let result = try await read([item(cite: 10, quote: "send a deck")], store: store)
        #expect(throws: (any Error).self) {
            try store.writer.write { try $0.execute(sql: "UPDATE drop_reason SET rule = 'malformed'") }
        }
        #expect(try store.queries.dropReasons(of: try #require(result.run)).first?.rule == .quoteNotInLines)
    }

    @Test func theMinimumQuoteStrengthStaysOffUntilAPersonSwitchesItOn() async throws {
        let store = try makeStore()
        #expect(try store.queries.verifierSettings() == Verifier.Settings())
        #expect(try await read([item(cite: 10, quote: "a")], store: store).items.count == 1)
        try store.saveVerifierSettings(Verifier.Settings(minimumQuoteWords: 3))
        let result = try await read([item(cite: 10, quote: "a")], store: store)
        #expect(result.items.isEmpty)
        #expect(try store.queries.dropReasons(of: try #require(result.run)).map(\.rule) == [.quoteTooShort])
    }

    @Test func aClaimWithACurlyQuoteIsKeptAndABadOneLeavesARow() async throws {
        let store = try makeStore()
        let line = Evidence(
            id: 3, start: t0, line: "Pitch: We\u{2019}ve raised $20 million.",
            quotable: ["We\u{2019}ve raised $20 million."])
        let good =
            #"{"line":3,"text":"Raised $20 million.","type":"funding","value":"$20 million","quote":"We've raised $20 million"}"#
        let bad = good.replacingOccurrences(of: "$20 million\"}", with: "$30 million\"}")
        let result = try await ClaimExtractor(
            model: RecordedModel(ScriptedModel(#"{"claims":[\#(good),\#(bad)]}"#), store: store),
            types: fundClaimTypes
        ).extract(deal: "d1", lines: [line])
        #expect(result.claims.count == 1 && result.dropped == 1)
        let rows = try store.queries.dropReasons(of: try #require(result.run))
        #expect(rows.map(\.rule) == [.quoteNotInLines] && rows.first?.part == "claims")
    }

    @Test func aStoreFromBeforeTheStepKeepsItsItemsAsUnlabelledOfUnknownAuthority() throws {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        let before = Schema.steps.prefix(while: { $0 != Schema.groundedFacts })
        try queue.write { db in
            for statement in before.joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = \(before.count)")
            try db.execute(
                sql: """
                    INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                    VALUES ('t', 'm', 'p', 0, 's', '2026-11-19T10:00:00Z', '2026-11-19T10:00:01Z', 'done')
                    """)
            try db.execute(
                sql: """
                    INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                        quote, created_at) VALUES ('t', 1, '2026-11-19', '', 'whatsapp', 3, 4, '2026-11-19T10:00:00Z',
                        '2026-11-19T10:00:00Z', '{}', 'kept words', '2026-11-19T12:00:00Z')
                    """)
        }
        let store = try Store(directory: folder)
        let old = try #require(
            try store.queries.items(of: "t", since: WorkDay(containing: t0.addingTimeInterval(-9e8))).first)
        #expect(old.quote == "kept words" && old.label == nil && old.authority == .unknown && old.quoteSpan == nil)
    }

    @Test func aFactThePersonTypedIsOwnWordsAndAModelFactWithNoProvenanceIsUnknown() async throws {
        let store = try makeStore()
        let events = [
            WorkEvent(id: "c", object: "deal-1", author: "Asha", clock: 1, at: t0, kind: .create, text: "deal"),
            WorkEvent(id: "t", object: "deal-1", author: "Asha", clock: 2, at: t0, kind: .title, text: "Acme"),
        ]
        let deal = try #require(WorkObject.fold(events, viewer: "Asha").first)
        try store.requireAction(of: deal, what: "Get the cap table", due: day, owner: "Asha")
        try store.setRevisit(of: deal, on: day, reason: nil)
        let typed =
            try store.queries.items(of: DealAction.task, since: day) + store.queries.items(of: Revisit.task, since: day)
        #expect(typed.count == 2 && typed.allSatisfy { $0.authority == .ownWords && $0.label == nil })

        let bare = EvidenceSet(
            lines: [Evidence(id: 10, start: t0, line: "Asha: login done", quotable: ["login done"])],
            context: ["members": ["Asha"]])
        let model = ScriptedModel(#"{"items":[\#(item(cite: 10, quote: "login done"))]}"#)
        let result = try await HelperReader(spec: .team, model: RecordedModel(model, store: store))
            .read(day: day, scope: "team", evidence: bare)
        #expect(result.items.first?.authority == .unknown && result.items.first?.label == nil)
    }
}
