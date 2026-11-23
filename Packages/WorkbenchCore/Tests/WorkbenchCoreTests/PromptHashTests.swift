import Testing

@testable import WorkbenchCore

struct PromptHashTests {
    private func hash<Task: FixedModelTask>(_: Task.Type) throws -> String {
        Digest.sha256(Task.instructions + "\n" + (try Task.schema.jsonText))
    }

    @Test func aPromptKeepsItsHashSoTheTrustItEarnedStays() throws {
        #expect(try hash(Briefer.self) == "224c9d5c6e03fac5e261f70a7d5a22b2af53a84098bd767ad2e5445566757dd0")
        #expect(try hash(Asker.self) == "f9f1b8580c7b66c819beb7e1bec2dc0af9d72ef124896878a89bbb785d7babcd")
        #expect(try hash(Drafter.self) == "da7ac701fed90cd1089c38389a992c3ae5ae76b0fe7d718379caa9a7b6cde413")
        #expect(try hash(Mochi.self) == "bc0221fc57dc722fca88dcf5ab86c2f600e92cd75e259dc7028f892416398b82")
        #expect(try hash(Summarizer.self) == "7747c46eb078acf8dbe9ca9578960c98152e31ee7081f56c47319f52bdd8ca43")
        #expect(try hash(Improver.self) == "5536115ac108de6b7c146b29ef9f7928ccf8c2e1237f0cf86fa0509eb276ed24")
    }
}
