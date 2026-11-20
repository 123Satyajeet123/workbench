import Foundation
import Testing

@testable import WorkbenchCore

/// Each caller says honestly which consent kinds its input holds.
struct CallSiteKindTests {
    private let today = WorkDay(containing: t0)

    private func item(_ id: Int64, _ source: SourceKind, on day: WorkDay? = nil, _ state: Mark = .proposed) -> Item {
        let day = day ?? today
        var item = Item(
            id: id, task: "t", day: day, scope: "", source: source, citeFirst: 1, citeLast: 1, start: day.start,
            end: day.start.addingTimeInterval(600), fields: ["task": "x"], quote: "q\(id)", run: 1)
        item.state = state
        return item
    }

    private func kinds(of run: RunID?, in store: Store) throws -> Set<SourceKind> {
        let run = try #require(run)
        return try #require(try store.queries.runText(of: run)).kinds
    }

    @Test func aBriefHoldsTheKindsOfTheItemsItSummarizes() async throws {
        let store = try makeStore()
        let briefer = Briefer(model: RecordedModel(ScriptedModel(#"{"headline":"","lines":[]}"#), store: store))
        let sources = [item(1, .whatsapp), item(2, .screen)].map {
            Briefer.Source(machine: "m", fields: ["task"], item: $0)
        }
        let brief = try #require(try await briefer.brief(sources, day: today))
        #expect(try kinds(of: brief.run, in: store) == [.whatsapp, .screen])
    }

    @Test func anImprovementHoldsTheKindsOfTheMarkedItemsItReads() async throws {
        let store = try makeStore()
        let devDays = (1...40).map { today.adding(days: -$0) }.filter { EvalSplit($0) == .dev }
        let marked = [
            item(1, .screen, on: devDays[0], .rejected), item(2, .screen, on: devDays[1], .rejected),
            item(3, .screen, on: devDays[2], .rejected),
        ]
        let improver = Improver(
            model: RecordedModel(
                ScriptedModel(#"{"kind":"add","text":"Leave out breaks.","why":"w","cites":[1]}"#), store: store))
        let run = try await improver.propose(spec: .timeline, marked: marked).run
        #expect(try kinds(of: run, in: store) == [.screen])
    }

    @Test func mochiHoldsTheKindOfTheBlocksItReads() async throws {
        let store = try makeStore()
        let blocks = (0..<3).map { item(Int64($0 + 1), .screen, on: today.adding(days: -$0)) }
        let mochi = Mochi(model: RecordedModel(ScriptedModel(#"{"proposals":[]}"#), store: store))
        let run = try await mochi.propose(blocks: blocks, roster: [], templates: [], earlier: []).run
        #expect(try kinds(of: run, in: store) == [.screen])
    }

    @Test func aDraftHoldsTheKindOfItsItem() async throws {
        let store = try makeStore()
        let machine = Machine(id: 1, name: "Pip", template: "team.ledger", spec: .team, state: .active)
        let drafter = Drafter(model: RecordedModel(ScriptedModel(#"{"to":"","text":"ok"}"#), store: store))
        let run = try await drafter.draft(item(1, .whatsapp), from: machine, founder: "Kabir").run
        #expect(try kinds(of: run, in: store) == [.whatsapp])
    }

    @Test func aQuestionHoldsTheKindsOfTheEntriesItWasGivenAndNoOther() async throws {
        let store = try makeStore()
        let entries = [
            MemoryEntry(id: "a", source: "s", text: "acme seed", quote: "acme seed", kinds: [.screen]),
            MemoryEntry(id: "b", source: "s", text: "acme note", quote: "acme note"),
            MemoryEntry(id: "c", source: "s", text: "unrelated chat", quote: "unrelated chat", kinds: [.whatsapp]),
        ]
        let asker = Asker(model: RecordedModel(ScriptedModel(#"{"answer":"","cites":[]}"#), store: store))
        let run = try await asker.ask("acme", entries: entries).run
        #expect(try kinds(of: run, in: store) == [.screen])
    }

    @Test func aHelperReadingHoldsItsSourceKind() async throws {
        let store = try makeStore()
        let evidence = EvidenceSet(lines: [
            Evidence(id: 1, start: t0, end: t0 + 60, line: "Brave — x", quotable: ["x"])
        ])
        let reader = HelperReader(
            spec: .timeline, model: RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store))
        let run = try await reader.read(day: today, scope: "", evidence: evidence).run
        #expect(try kinds(of: run, in: store) == [.screen])
    }
}
