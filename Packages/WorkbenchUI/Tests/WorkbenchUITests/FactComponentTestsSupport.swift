import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Facts for the component tests: items built by hand, and the sample day behind real models.
enum FactFixture {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static var today: WorkDay { WorkDay(containing: now) }

    static func item(
        _ id: Int64, person: String = "Asha", project: String = "Login", due: Int? = nil,
        state: Mark = .proposed, askedWith: Double? = nil, task: String = HelperSpec.team.task
    ) -> Item {
        var item = Item(
            id: id, task: task, day: today, scope: "sample", source: .whatsapp, citeFirst: id, citeLast: id,
            start: now.addingTimeInterval(-26 * 3600), end: now.addingTimeInterval(-26 * 3600),
            fields: [
                "person": person, "project": project, "kind": "commitment", "text": "Ship the login API",
            ], quote: "login API aaj raat tak", state: state, run: nil, askedWith: askedWith,
            due: due.map {
                Due(
                    utc: today.adding(days: $0).start, zone: TimeZone.current.identifier, source: .stated,
                    precision: .day)
            })
        item.id = id
        return item
    }

    static func row(
        _ id: Int64, title: String = "Ship the login API", reason: FactReason? = nil, person: String = "Asha",
        due: Int? = nil, askedWith: Double? = nil
    ) -> FactRow {
        FactRow(
            item: item(id, person: person, due: due, askedWith: askedWith), title: title, reason: reason)!
    }

    /// The sample day behind a Today model, a review queue and the fact machine's own model.
    struct Day {
        let store: Store
        let crew: Crew
        let today: TodayModel
        let review: ReviewModel

        var pip: HelperModel { crew.team! }

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

/// A surface that holds a set of handled facts, so a flow test needs no store.
final class FakeActing: FactActing {
    private(set) var handled: [Int64] = []
    var fails = false

    func offered(for item: Item) -> [FactAction] {
        FactAction.offered(for: item, isOpenFact: true).filter { _ in !handled.contains(item.id ?? 0) }
    }

    func perform(_ action: FactAction, on items: [Item], surface: Surface) throws -> (() -> Void)? {
        if fails { throw FactActionError(reason: "The disk is full.") }
        let ids = items.compactMap(\.id)
        handled += ids
        return { [self] in handled.removeAll { ids.contains($0) } }
    }
}
