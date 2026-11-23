import CaptureService
import Foundation
import LocalSources
import SQLite3
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The model's input and a proof card read the same stored lines, and a card keeps what the model saw.
@Suite struct ProofCardTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private let reply =
        #"{"items":[{"person":"Asha","project":"Login","kind":"done","text":"Login API","eta":"","asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":@login API done@,"quote":"login API done"}]}"#

    private struct Scene {
        let team: HelperModel
        let source: WhatsAppSource
        let store: Store
        let model: ScriptedModel
        let container: URL
    }

    private func read() async throws -> Scene {
        let now = noon
        let store = try scratchStore(clock: { now })
        let container = try whatsApp(at: noon)
        let model = ScriptedModel(reply)
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: HelperSpec.team.task,
            founder: { "Kabir" }, container: container)
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        let team = HelperModel(
            machine: .test(.team, "Pip"), source: source, store: store,
            makeModel: { _ in RecordedModel(model, store: store) })
        await team.read()
        return Scene(team: team, source: source, store: store, model: model, container: container)
    }

    /// The numbered lines of a model input: `[number] time sender: words`.
    private func shownLines(_ input: String) -> [(number: Int64, text: String)] {
        input.split(separator: "\n").compactMap { line in
            guard let match = line.wholeMatch(of: #/\[(\d+)\] \S+ (.+)/#), let number = Int64(match.output.1) else {
                return nil
            }
            return (number, String(match.output.2))
        }
    }

    @Test func theModelInputAndTheProofCardShowTheSameStoredLines() async throws {
        let scene = try await read()
        let item = try #require(scene.team.items.first)
        let input = try #require(scene.model.inputs.withLock { $0.first })
        let proof = try await scene.source.proof(of: item, reach: 5)
        let shown = shownLines(input)
        #expect(proof.map(\.id) == shown.map(\.number), "the card holds the lines, under the numbers, the model read")
        #expect(proof.map(\.text) == shown.map(\.text))
        #expect(proof.filter(\.isCited).map(\.text) == ["Asha: login API done"])
        #expect(try scene.store.queries.window(of: #require(item.run)).count == proof.count)
    }

    @Test func aCardShowsTheSameQuoteAfterTheChatIsEditedAndAfterTheMessageIsDeleted() async throws {
        let scene = try await read()
        let item = try #require(scene.team.items.first)
        let day = WorkDay(containing: noon)

        try runSQL("UPDATE ZWAMESSAGE SET ZTEXT = 'login API NOT done' WHERE Z_PK = 11", in: scene.container)
        let edited = try await scene.source.evidence(on: day).lines.map(\.line)
        #expect(edited.contains("Asha: login API NOT done") && !edited.contains("Asha: login API done"))
        #expect(
            try await scene.source.proof(of: item, reach: 0).map(\.text) == ["Asha: login API done"],
            "the card still shows what the model read")

        try runSQL("UPDATE ZWAMESSAGE SET ZMESSAGETYPE = 14, ZTEXT = NULL WHERE Z_PK = 11", in: scene.container)
        let after = try await scene.source.evidence(on: day).lines.map(\.line)
        #expect(
            !after.contains { $0.contains("login API") || $0.contains(WhatsAppSource.deletedWords) },
            "a deleted message is not a line for a model")
        let card = try await scene.source.proof(of: item, reach: 0)
        #expect(card.map(\.text) == ["Asha: This message was deleted"], "time and sender stay, the words do not")
        #expect(card.first?.time != nil)
        let stored = try scene.store.queries.currentLines(
            in: [teamJID], from: day.start, to: day.end)
        #expect(
            !stored.contains { $0.text.contains("login API") }, "no version of the text stays as a current line")
    }

    @Test func aChatThatCannotBeReadStopsTheReadInsteadOfServingOlderLines() async throws {
        let scene = try await read()
        try scene.source.preview(ChatSelection(nameContains: "a", directWithMembers: false))
        try scene.source.choose(scene.source.matching)
        await #expect(throws: (any Error).self, "the family group has no member to name its audience") {
            _ = try await scene.source.evidence(on: WorkDay(containing: noon))
        }
    }

    @Test func aFactMadeBeforeRunsKeptWindowsStillResolvesThroughItsOldCitation() async throws {
        let scene = try await read()
        let item = try #require(scene.team.items.first)
        var old = item
        old.citeFirst = 11
        old.citeLast = 11
        old.run = nil
        #expect(try await scene.source.proof(of: old, reach: 0).map(\.text) == ["Asha: login API done"])
    }
}

private func runSQL(_ sql: String, in container: URL) throws {
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    guard sqlite3_open(container.appending(path: "ChatStorage.sqlite").path, &db) == SQLITE_OK,
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    else { throw CocoaError(.fileWriteUnknown) }
}
