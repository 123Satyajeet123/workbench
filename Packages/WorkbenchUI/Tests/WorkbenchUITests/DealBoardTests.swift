import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct DealBoardTests {
    @Test func aDealIntakeItemBecomesADealThatMovesTakesNotesAndArchives() async throws {
        let store = try scratchStore()
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Aditya" }, notifier: FakeNotifier())
        let catalog = TeamCatalogModel(store: store, crew: crew, author: { "Aditya" }, secrets: MemorySecrets())
        let deals = DealsModel(store: store, catalog: catalog)
        let machine = try store.createMachine(from: .dealIntake, name: "Deal intake")
        let intake = HelperModel(
            machine: machine, source: try PageSource(store: store, task: machine.task), store: store,
            makeModel: { _ in RecordedModel(ScriptedModel("{}"), store: store) }, notifier: FakeNotifier())
        let item = Item(
            id: 7, task: machine.task, day: WorkDay(containing: .now), scope: "", source: .screenText, citeFirst: 1,
            citeLast: 1, start: .now, end: .now, fields: ["company": "Acme", "rating": "hot"],
            quote: "Acme is raising a 2M seed", run: 1)

        let id = try #require(await deals.newDeal(from: item, of: intake))
        var deal = try #require(deals.deal(id))
        #expect(deal.title == "Acme" && deals.deals(in: "Inbox").map(\.id) == [id])
        #expect(deal.items.map(\.item.quote) == ["Acme is raising a 2M seed"], "the founder sees their own item")
        #expect(deal.items.first?.item.audience == ["Aditya"], "a page item's audience is its owner alone")

        deals.move(deal, to: "Founder meeting")
        deals.note(try #require(deals.deal(id)), "Strong founder; ask about churn.")
        deals.claim(try #require(deals.deal(id)))
        deal = try #require(deals.deal(id))
        #expect(deals.deals(in: "Inbox").isEmpty && deals.deals(in: "Founder meeting").map(\.id) == [id])
        #expect(deal.notes.map(\.text) == ["Strong founder; ask about churn."] && deal.holder == "Aditya")
        #expect(deal.history.map(\.kind) == [.create, .title, .stage, .link, .stage, .note, .claim])

        deals.archive(deal)
        #expect(deals.deals.isEmpty)
    }

    @Test func aDealsLinkedItemsGiveTheMemoryTheKindOfTheirSourceAndAnOldOneIsUnknown() async throws {
        let store = try scratchStore()
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Aditya" }, notifier: FakeNotifier())
        let deals = DealsModel(
            store: store,
            catalog: TeamCatalogModel(store: store, crew: crew, author: { "Aditya" }, secrets: MemorySecrets()))
        let id = try #require(deals.create(title: "Acme"))
        func linked(_ source: String) throws -> LinkedItem {
            try JSONDecoder().decode(
                LinkedItem.self,
                from:
                    Data(
                        #"{"machine":"Intake","day":"2026-09-21","columns":[],"fields":{},"quote":"Acme \#(source)","state":"proposed","audience":["Aditya"]\#(source == "old" ? "" : #","source":"whatsapp""#)}"#
                            .utf8)
            )
        }
        let first = try store.queries.nextClock()
        try store.append(
            ["chat", "old"].enumerated().map { index, source in
                WorkEvent(
                    object: id, author: "Aditya", clock: first + index, at: store.clock(), kind: .link,
                    item: try? linked(source))
            })
        deals.refresh()
        let memory = MemoryModel(store: store, crew: crew, deals: deals)
        let entries = try memory.entries().filter { $0.id.hasPrefix("link:") }
        let chat = try #require(entries.first { $0.quote == "Acme chat" })
        let old = try #require(entries.first { $0.quote == "Acme old" })
        #expect(chat.kinds == [.whatsapp] && !chat.kindUnknown)
        #expect(old.kinds.isEmpty && old.kindUnknown)
    }

    @Test func theMemoryAnswersFromDealNotesWithACitationAndLeavesOutItemsMarkedWrong() async throws {
        let store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Aditya" }, notifier: FakeNotifier())
        let deals = DealsModel(
            store: store,
            catalog: TeamCatalogModel(store: store, crew: crew, author: { "Aditya" }, secrets: MemorySecrets()))
        let id = try #require(deals.create(title: "Acme"))
        deals.note(try #require(deals.deal(id)), "Acme founder strong; churn unclear.")
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let (_, run) = try await model.generate(
            Nothing.self, schema: .object([.init("items", .array(.string))]), task: HelperSpec.timeline.task,
            instructions: "v", input: "x", holding: [])
        let day = WorkDay(containing: store.clock())
        let items = ["Acme call prep", "Acme wrong block"].enumerated().map { index, quote in
            Item(
                task: HelperSpec.timeline.task, day: day, scope: "", source: .screen, citeFirst: Int64(index),
                citeLast: Int64(index), start: day.start.addingTimeInterval(Double(index) * 600),
                end: day.start.addingTimeInterval(Double(index) * 600 + 300), fields: ["task": quote], quote: quote,
                run: run)
        }
        try store.saveReading(
            .init(items: items, dropped: 0, run: run), of: .timeline, day: day, scope: "",
            grant: CapturePolicy(switches: [.screen: true]).authorize(CaptureRequest(kind: .screen), at: store.clock())
                .grant!)
        let wrong = try #require(try store.queries.items(of: HelperSpec.timeline.task, day: day, scope: "").last)
        try store.mark(item: try #require(wrong.id), as: .rejected)
        let note = try #require(deals.deal(id)?.notes.first)
        let scripted = ScriptedModel(
            #"{"answer":"The founder looks strong; churn is unclear.","cites":[{"id":"note:\#(note.id)","quote":"churn unclear"}]}"#
        )
        let memory = MemoryModel(
            store: store, crew: crew, deals: deals, makeModel: { _ in RecordedModel(scripted, store: store) })
        #expect(
            try memory.entries().map(\.quote).sorted() == ["Acme call prep", "Acme founder strong; churn unclear."])
        await memory.ask("What do we know about Acme?")
        #expect(memory.answer?.text == "The founder looks strong; churn is unclear.")
        #expect(memory.answer?.cited.map(\.source) == ["Acme · note by Aditya"])
    }
}
