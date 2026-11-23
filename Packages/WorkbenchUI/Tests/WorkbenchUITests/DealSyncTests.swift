import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Two Macs, one team folder: Kabir's and Asha's. Each sends only its own envelopes.
@Suite struct DealSyncTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private func mac(_ me: String, teammate: String, folder: URL) throws -> (DealsModel, TeamCatalogModel, Store) {
        let now = noon
        let store = try scratchStore(clock: { now })
        try store.saveTeam(
            Team(name: "Fund", people: [.init(name: me, role: "", isMe: true), .init(name: teammate, role: "")]))
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { me }, notifier: FakeNotifier())
        let catalog = TeamCatalogModel(store: store, crew: crew, author: { me }, secrets: MemorySecrets())
        catalog.choose(folder)
        return (DealsModel(store: store, catalog: catalog), catalog, store)
    }

    @Test func aDealTravelsThroughTheFolderButAPrivateItemNeverLeavesAndConcurrentMovesShowBoth() async throws {
        let folder = scratchFolder()
        let (kabir, kabirCatalog, kabirStore) = try mac("Kabir", teammate: "Asha", folder: folder)
        let (asha, ashaCatalog, ashaStore) = try mac("Asha", teammate: "Kabir", folder: folder)
        formTeam(founder: kabirCatalog, others: [ashaCatalog])

        // Pip on Kabir's Mac reads the team group, where Asha is linked as a member; the timeline reads his screen.
        let capture = try CaptureService(store: kabirStore)
        let source = try WhatsAppSource(
            store: kabirStore, capture: capture, task: HelperSpec.team.task, founder: { "Kabir" },
            container: try whatsApp(at: noon))
        try source.loadGroups()
        try source.choose(try #require(source.groups.first { $0.jid == teamJID }))
        let pip = HelperModel(
            machine: .test(.team, "Pip"), source: source, store: kabirStore,
            makeModel: { _ in
                RecordedModel(
                    ScriptedModel(
                        #"{"items":[{"person":"Asha","project":"Login","kind":"done","text":"Login API","eta":"","asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":@login API done@,"quote":"login API done"}]}"#
                    ), store: kabirStore)
            }, notifier: FakeNotifier())
        await pip.read()
        let ashaPerson = try #require(try kabirStore.queries.team()?.people.first { $0.name == "Asha" })
        try kabirStore.link(ashaPerson, whatsapp: "a@s.whatsapp.net")
        let screenItem = Item(
            task: "day.timeline", day: WorkDay(containing: noon), scope: "", source: .screen, citeFirst: 1, citeLast: 1,
            start: noon, end: noon, fields: ["task": "Read the term sheet"], quote: "Term sheet - Acme.pdf", run: 1)
        let timeline = HelperModel(
            machine: .test(.timeline, "Timeline"), source: ScreenSource(store: kabirStore), store: kabirStore,
            makeModel: { _ in RecordedModel(ScriptedModel("{}"), store: kabirStore) }, notifier: FakeNotifier())

        let id = try #require(kabir.create(title: "Acme"))
        await kabir.link(try #require(pip.items.first), from: pip, to: id)
        await kabir.link(screenItem, from: timeline, to: id)
        #expect(try #require(kabir.deal(id)).items.count == 2, "Kabir sees both of his items")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "events").path), "no plaintext log")

        asha.refresh()
        let seen = try #require(asha.deal(id))
        #expect(seen.title == "Acme" && seen.stageLabels == ["Inbox"])
        #expect(seen.items.map(\.item.quote) == ["login API done"], "the group item came; the screen item stayed")
        #expect(!(try ashaStore.queries.workEvents()).contains { $0.item?.quote == "Term sheet - Acme.pdf" })

        asha.move(seen, to: dealStage("Screen"))
        kabir.move(try #require(kabir.deal(id)), to: dealStage("Diligence"))
        asha.refresh()
        kabir.refresh()
        #expect(try #require(asha.deal(id)).stageLabels == ["Screen", "Diligence"])
        #expect(try #require(kabir.deal(id)).stageLabels == ["Screen", "Diligence"])

        kabir.move(try #require(kabir.deal(id)), to: dealStage("Decision"))
        asha.refresh()
        #expect(try #require(asha.deal(id)).stageLabels == ["Decision"])
        let count = try ashaStore.queries.workEvents().count
        asha.refresh()
        #expect(try ashaStore.queries.workEvents().count == count, "reading the logs again adds nothing")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["sync"])
    }
}
