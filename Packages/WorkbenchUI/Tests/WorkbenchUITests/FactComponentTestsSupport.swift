import AppKit
import CaptureService
import Foundation
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Facts for the component tests: items built by hand, and the sample day behind real models.
enum FactFixture {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static var today: WorkDay { WorkDay(containing: now) }

    static func item(
        _ id: Int64, person: String = "Asha", project: String = "Login", due: Int? = nil,
        state: Mark = .proposed, askedWith: Double? = nil, task: String = HelperSpec.team.task,
        quote: String = "login API aaj raat tak"
    ) -> Item {
        var item = Item(
            id: id, task: task, day: today, scope: "sample", source: .whatsapp, citeFirst: id, citeLast: id,
            start: now.addingTimeInterval(-26 * 3600), end: now.addingTimeInterval(-26 * 3600),
            fields: [
                "person": person, "project": project, "kind": "commitment", "text": "Ship the login API",
            ], quote: quote, state: state, run: nil, askedWith: askedWith,
            due: due.map {
                Due(
                    utc: today.adding(days: $0).start, zone: TimeZone.current.identifier, source: .stated,
                    precision: .day)
            })
        item.id = id
        return item
    }

    static func row(
        _ id: Int64, title: String = "Ship the login API", person: String = "Asha", project: String = "Login",
        chat: String? = nil, due: Int? = nil, askedWith: Double? = nil, quote: String = "login API aaj raat tak"
    ) -> FactRow {
        FactRow(
            item: item(id, person: person, project: project, due: due, askedWith: askedWith, quote: quote),
            title: title, chat: chat)!
    }

    /// The sample day behind a Today model, a review queue and the fact machine's own model.
    struct Day {
        let store: Store
        let crew: Crew
        let today: TodayModel
        let review: ReviewModel

        var pip: HelperModel { crew.factKeepers.first! }

        /// Open facts the app did not pick at random: the sample marks a random few of its facts as audit picks.
        func plainFacts() throws -> [Item] {
            try store.queries.items(of: HelperSpec.team.task, on: WorkDay(containing: store.clock()))
                .filter { $0.askedWith == nil && ["blocker", "question", "commitment", "plan"].contains($0["kind"]) }
        }

        func fact(_ id: Int64) throws -> Item {
            try #require(
                store.queries.items(of: HelperSpec.team.task, on: WorkDay(containing: store.clock())).first {
                    $0.id == id
                })
        }
    }

    static func day() async throws -> Day {
        let clock = TestClock(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: now)!)
        let store = try scratchStore(clock: { clock.now })
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" }, notifier: FakeNotifier())
        try await TodaySample.populate(store: store, crew: crew, withSummaries: false)
        return Day(
            store: store, crew: crew, today: TodayModel(store: store, crew: crew),
            review: ReviewModel(store: store, crew: crew))
    }
}

/// A view drawn through AppKit, which also draws menus and other native controls that `ImageRenderer` leaves blank.
@MainActor func renderedPNG(of view: some View, mode: String) throws -> Data {
    let host = NSHostingView(rootView: view)
    let appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
    host.appearance = appearance
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: host.fittingSize), styleMask: [], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let bounds = host.bounds
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * 2, pixelsHigh: Int(bounds.height) * 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = bounds.size
    host.cacheDisplay(in: bounds, to: bitmap)
    return try #require(bitmap.representation(using: .png, properties: [:]))
}
