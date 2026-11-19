import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct AskTests {
    private let entries = [
        MemoryEntry(
            id: "item:1", source: "Deal intake · 2026-09-21", text: "Acme fintech seed hot — Acme is raising a 2M seed",
            quote: "Acme is raising a 2M seed"),
        MemoryEntry(
            id: "note:a", source: "Acme · Kabir", text: "Acme founder strong; churn unclear",
            quote: "Acme founder strong; churn unclear"),
        MemoryEntry(
            id: "item:2", source: "Pip · 2026-09-21", text: "Asha done Login API — login API done",
            quote: "login API done"),
    ]

    private func asker(_ reply: String) throws -> (Asker, ScriptedModel) {
        let scripted = ScriptedModel(reply)
        return (Asker(model: RecordedModel(scripted, store: try makeStore())), scripted)
    }

    @Test func searchFindsTheEntriesThatShareTheQuestionsWords() throws {
        #expect(try Asker.search("How much is Acme raising?", in: entries).first?.id == "item:1")
        #expect(try Asker.search("login", in: entries).map(\.id) == ["item:2"])
        #expect(try Asker.search("?!", in: entries).isEmpty)
    }

    @Test func anAnswerIsKeptOnlyWithCitationsThatQuoteTheirEntries() async throws {
        let (asker, scripted) = try asker(
            #"{"answer":"Acme raises a 2M seed; the founder looks strong.","cites":[{"id":"item:1","quote":"raising a 2M seed"},{"id":"note:a","quote":"founder strong"}]}"#
        )
        let (answer, run) = try await asker.ask("What do we know about Acme?", entries: entries)
        #expect(run != nil && answer.text == "Acme raises a 2M seed; the founder looks strong.")
        #expect(answer.cited.map(\.id) == ["item:1", "note:a"])
        #expect(!(scripted.inputs.withLock { $0.first } ?? "").contains("login API done"), "only matching entries go")
    }

    @Test func aCitationOutsideTheEntriesOrAQuoteTheEntryLacksIsRefused() throws {
        let given = entries
        let unknown = Asker.Reply(answer: "x", cites: [.init(id: "item:99", quote: "anything")])
        let misquoted = Asker.Reply(answer: "x", cites: [.init(id: "item:1", quote: "raising a 5M series A")])
        #expect(throws: Asker.Refusal.badCitation("item:99")) { try Asker.checked(unknown, given: given) }
        #expect(throws: Asker.Refusal.badCitation("item:1")) { try Asker.checked(misquoted, given: given) }
        let uncited = Asker.Reply(answer: "Acme raised 10M.", cites: [])
        #expect(try Asker.checked(uncited, given: given).text == nil, "an uncited claim is never shown")
    }

    @Test func withNothingMatchingNoModelRuns() async throws {
        let (asker, scripted) = try asker(#"{"answer":"","cites":[]}"#)
        let (answer, run) = try await asker.ask("weather in Paris", entries: entries)
        #expect(run == nil && answer.text == nil && scripted.inputs.withLock { $0.isEmpty })
    }
}
