import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct CatalogTests {
    @Test func aSharedMachineCarriesItsSpecAndCountsButNeverItsItems() async throws {
        let store = try makeStore()
        let machine = try store.createMachine(from: .timeline, name: "Deck triage")
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let (_, run) = try await model.generate(
            HelperReader.Reply.self, schema: .object([.init("items", .array(.string))]), task: machine.task,
            instructions: machine.spec.brief,
            input: "x")
        let day = WorkDay(containing: t0)
        let secret = "Acme raises at a 40 crore valuation"
        let item = Item(
            task: machine.task, day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1, start: day.start,
            end: day.start.addingTimeInterval(600), fields: ["task": secret], quote: secret, run: run)
        try store.saveReading(
            .init(items: [item], dropped: 1, run: run), of: machine.spec, day: day, scope: "", grant: grant(.screen),
            pick: { _ in 0 })
        try store.mark(
            item: try #require(store.queries.items(of: machine.task, day: day, scope: "").first?.id), as: .confirmed)

        let record = SharedMachine.Record(task: machine.task, quality: try store.queries.quality())
        #expect(record.runs == 1 && record.kept == 1 && record.dropped == 1 && record.audited == 1)
        #expect(record.auditedPrecision == 1)
        let folder = temporaryDirectory()
        try SharedMachine(author: "Kabir", machine: machine, record: record, at: t0).write(to: folder)
        let file = try #require(
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("Acme") && !text.contains("crore"), "no item text leaves the Mac")
        #expect(text.contains(machine.spec.brief.prefix(20)) && text.contains("Deck triage"))
    }

    @Test func eachAuthorWritesTheirOwnFileAndTheFolderReadsBackNewestFirst() throws {
        let folder = temporaryDirectory()
        let mine = Machine(id: 1, name: "Pip", template: "team.ledger", spec: .team, state: .active)
        var theirs = mine
        theirs.name = "Inbound deals"
        try SharedMachine(author: "Kabir", machine: mine, record: .init(), at: t0).write(to: folder)
        try SharedMachine(author: "Aditya", machine: theirs, record: .init(), at: t0.addingTimeInterval(60)).write(
            to: folder)
        try Data("not json".utf8).write(to: folder.appending(path: "broken.json"))
        let (machines, unreadable) = SharedMachine.read(from: folder)
        #expect(machines.map(\.author) == ["Aditya", "Kabir"])
        #expect(unreadable == ["broken.json"])
        try SharedMachine.remove(author: "Kabir", parts: [mine.task], from: folder)
        #expect(SharedMachine.read(from: folder).files.map(\.author) == ["Aditya"])
        #expect(SharedMachine.fileName(author: "../evil", parts: ["a/b"]) == "evil--ab.json")
    }
}
