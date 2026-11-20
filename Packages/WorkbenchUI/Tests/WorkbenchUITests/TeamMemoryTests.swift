import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Two Macs share one team folder: Kabir's shares a day; Asha's and Bharat's read it.
@Suite struct TeamMemoryTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()
    private let reply = #"""
        {"items":[{"person":"Asha","project":"Login","kind":"done","text":"Login API","eta":"","asks":"team","stance":"said","cite":11,"quote":"login API done"}],"closes":[]}
        """#

    /// Kabir's Mac: his team, Pip reading the team group's day, and the team folder.
    private func kabir(teammates: [String], folder: URL) async throws -> (TeamCatalogModel, HelperModel, Store) {
        let now = noon
        let store = try scratchStore(clock: { now })
        try store.saveTeam(
            Team(
                name: "Brave",
                people: [.init(name: "Kabir", role: "Founder", isMe: true)]
                    + teammates.map { .init(name: $0, role: "") }
            ))
        let capture = try CaptureService(store: store)
        let source = try WhatsAppSource(
            store: store, capture: capture, task: HelperSpec.team.task, founder: { "Kabir" },
            container: try whatsApp(at: noon))
        try source.loadGroups()
        try source.choose(try #require(source.groups.first { $0.jid == teamJID }))
        let scripted = ScriptedModel(reply)
        let pip = HelperModel(
            machine: .test(.team, "Pip"), source: source, store: store,
            makeModel: { _ in RecordedModel(scripted, store: store) }, notifier: FakeNotifier())
        await pip.read()
        let crew = Crew(store: store, capture: capture, founder: { "Kabir" }, notifier: FakeNotifier())
        let catalog = TeamCatalogModel(store: store, crew: crew, author: { "Kabir" })
        catalog.choose(folder)
        return (catalog, pip, store)
    }

    /// A teammate's Mac reading the same folder.
    private func mac(of person: String, folder: URL) throws -> TeamCatalogModel {
        let store = try scratchStore()
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { person }, notifier: FakeNotifier())
        let catalog = TeamCatalogModel(store: store, crew: crew, author: { person })
        catalog.choose(folder)
        return catalog
    }

    private func person(_ name: String, in store: Store) throws -> Team.Person {
        try #require(try store.queries.team()?.people.first { $0.name == name })
    }

    @Test func aGroupDayGoesOnlyOnceEveryTeammateIsLinkedToAMemberOfTheGroup() async throws {
        let folder = scratchFolder()
        let (catalog, pip, store) = try await kabir(teammates: ["Asha"], folder: folder)
        #expect(pip.items.map(\.quote) == ["login API done"])

        await catalog.share(day: pip)
        #expect(catalog.refusal?.missing.map(\.name) == ["Asha"])
        #expect(catalog.refusal?.group.map(\.name) == ["Asha", "Bharat"])
        #expect(!catalog.isShared(day: pip) && SharedDay.read(from: folder).files.isEmpty)

        let asha = try #require(catalog.refusal?.group.first { $0.name == "Asha" })
        await catalog.link(try person("Asha", in: store), to: asha, for: pip)
        #expect(catalog.refusal == nil)
        #expect(SharedDay.read(from: folder).files.isEmpty, "linking checks again; it never sends")

        await catalog.share(day: pip)
        #expect(catalog.isShared(day: pip))
        #expect(try store.queries.actions().map(\.kind) == ["share_day"])

        let ashasMac = try mac(of: "Asha", folder: folder)
        let day = try #require(ashasMac.teammatesDays.first)
        #expect(day.author == "Kabir" && day.machine == "Pip")
        #expect(day.entries.map(\.quote) == ["login API done"])
        #expect(try mac(of: "Bharat", folder: folder).teammatesDays.isEmpty, "Bharat is not in Kabir's audience")

        catalog.unshare(day: pip)
        #expect(ashasMac.teammatesDays.count == 1)
        ashasMac.refresh()
        #expect(ashasMac.teammatesDays.isEmpty)
        #expect(try store.queries.actions().map(\.kind) == ["share_day", "unshare_day"])
    }

    @Test func oneTeammateOutsideTheGroupHoldsTheWholeDayBack() async throws {
        let folder = scratchFolder()
        let (catalog, pip, store) = try await kabir(teammates: ["Asha", "Dev"], folder: folder)
        await catalog.share(day: pip)
        let asha = try #require(catalog.refusal?.group.first { $0.name == "Asha" })
        await catalog.link(try person("Asha", in: store), to: asha, for: pip)
        await catalog.link(
            try person("Dev", in: store), to: .init(jid: "d@s.whatsapp.net", name: "Dev"), for: pip)
        await catalog.share(day: pip)
        #expect(catalog.refusal?.missing.map(\.name) == ["Dev"])
        #expect(SharedDay.read(from: folder).files.isEmpty)
        #expect(try store.queries.actions().isEmpty)
    }

    @Test func screenItemsNeverLeaveTheMac() async throws {
        let now = noon
        let store = try scratchStore(clock: { now })
        try store.saveTeam(
            Team(name: "Brave", people: [.init(name: "Kabir", role: "", isMe: true), .init(name: "Asha", role: "")]))
        try store.savePolicy(CapturePolicy(switches: [.screen: true]))
        let today = WorkDay(containing: now)
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let (_, run) = try await model.generate(
            Nothing.self, schema: .object([.init("items", .array(.string))]), task: HelperSpec.timeline.task,
            instructions: "v1",
            input: "x", holding: [])
        let block = Item(
            task: HelperSpec.timeline.task, day: today, scope: "", source: .screen, citeFirst: 1, citeLast: 1,
            start: now, end: now, fields: ["task": "Mail to an LP"], quote: "Re: term sheet", run: run)
        try store.saveReading(
            .init(items: [block], dropped: 0, run: run), of: .timeline, day: today, scope: "",
            grant: try await store.grant(for: .screen, at: now))
        let timeline = HelperModel(
            machine: .test(.timeline, "Timeline"), source: ScreenSource(store: store), store: store,
            makeModel: { _ in model }, notifier: FakeNotifier())
        timeline.reload()
        #expect(timeline.items.count == 1)
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" }, notifier: FakeNotifier())
        let catalog = TeamCatalogModel(store: store, crew: crew, author: { "Kabir" })
        let folder = scratchFolder()
        catalog.choose(folder)
        await catalog.share(day: timeline)
        #expect(catalog.refusal?.missing.map(\.name) == ["Asha"] && catalog.refusal?.group.isEmpty == true)
        #expect(SharedDay.read(from: folder).files.isEmpty)
    }
}
