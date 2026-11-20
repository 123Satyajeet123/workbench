import AppKit
import CaptureService
import Foundation
import LocalSources
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Today, People and Projects drawn over a scratch store with the sample day, to a PNG for a person to look at. The
/// folder comes from `TODAY_PREVIEW_DIR`, else the temporary folder.
@Suite struct TodayRenderTests {
    private func brief() throws -> MorningBrief {
        let json = """
            {"day":"2026-09-20","headline":"Ask Asha for the signing key before the OTA slips.","lines":[
            {"kind":"ask","basis":"seen","text":"Raj waits on you to pick USD or INR.","cites":[3]},
            {"kind":"happened","basis":"seen","text":"Asha shipped OTA 4.1.11.","cites":[7]}],"unseen":[],"dropped":0}
            """
        return try JSONDecoder().decode(MorningBrief.self, from: Data(json.utf8))
    }

    private func folder() -> URL {
        ProcessInfo.processInfo.environment["TODAY_PREVIEW_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
    }

    private func png(of view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func sampleDay(withSummaries: Bool = true) async throws -> TodayModel {
        let store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" }, notifier: FakeNotifier())
        try await TodaySample.populate(store: store, crew: crew, withSummaries: withSummaries)
        return TodayModel(store: store, crew: crew)
    }

    @Test func todayIsDrawnWithItsSectionsInOrder() async throws {
        let model = try await sampleDay()
        let data = try png(of: TodayFrame(model: model, brief: try brief()))
        try data.write(to: folder().appending(path: "today-summaries.png"))
        #expect(data.count > 20_000)
    }

    @Test func peopleAndProjectsAreDrawn() async throws {
        let model = try await sampleDay()
        for (name, groups) in [("people", model.people), ("projects", model.projectGroups)] {
            let view = FactGroupsBody(groups: groups, empty: "None.", model: model)
                .padding(Space.l).frame(width: 760, alignment: .topLeading)
                .background(Color(nsColor: .textBackgroundColor))
            let data = try png(of: view)
            try data.write(to: folder().appending(path: "\(name)-preview.png"))
            #expect(data.count > 10_000)
        }
    }

    @Test func anEmptyDayIsDrawnAsOneLine() async throws {
        let store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        let model = TodayModel(store: store, crew: crew)
        #expect(model.isEmpty)
        let data = try png(of: TodayFrame(model: model))
        try data.write(to: folder().appending(path: "today-no-facts.png"))
        #expect(data.count > 1000)
    }

    @Test func todayIsDrawnForADayWithFactsAndNoSummaries() async throws {
        let model = try await sampleDay(withSummaries: false)
        #expect(model.team.isEmpty && !model.unsummarized.isEmpty)
        let data = try png(of: TodayFrame(model: model))
        try data.write(to: folder().appending(path: "today-facts-without-summaries.png"))
        #expect(data.count > 20_000)
    }

    @Test func crewAndAMachinePageAreDrawnOverTheSampleDay() async throws {
        guard case .ready(let session) = AppLaunch.start(storeFolder: scratchFolder()) else {
            Issue.record("the scratch session did not start")
            return
        }
        try await TodaySample.populate(store: session.store, crew: session.crew, scope: teamJID)
        session.runs.refresh()
        let pip = try #require(session.crew.machines.first { $0.spec.task == HelperSpec.team.task })
        let source = try WhatsAppSource(
            store: session.store, capture: try CaptureService(store: session.store), task: pip.spec.task,
            founder: { "Kabir" }, container: try whatsApp(at: .now))
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        let ready = HelperModel(
            machine: pip.machine, source: source, store: session.store, makeModel: nil,
            notifications: session.crew.notifications)
        let column = Page<EmptyView, EmptyView>.columnWidth
        let crew = CrewBody(open: { _ in }).environment(session).padding(Space.l).frame(
            width: column, alignment: .topLeading
        ).clipped()
        let machine = HelperContent(model: ready).environment(session).padding(Space.l).frame(
            width: column, alignment: .topLeading
        ).clipped()
        for (name, view) in [("crew", AnyView(crew)), ("machine", AnyView(machine))] {
            let data = try png(of: view.background(Color(nsColor: .textBackgroundColor)))
            try data.write(to: folder().appending(path: "\(name)-preview.png"))
            #expect(data.count > 10_000)
        }
    }
}
