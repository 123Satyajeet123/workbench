import CaptureService
import Foundation
import Observation
import WorkbenchCore

/// Startups found on the web for the investor's criteria. The switch is the web research consent: with it off the
/// machine is not ready and nothing is sent. A run goes through `WebSession`, which checks the consent, the key and
/// the monthly cap before any search. The candidates stay in the review list until the investor marks them.
@Observable
final class OutboundSource: MachineSource {
    /// How long a candidate stays in the review list.
    static let listedDays = 120

    private(set) var items: [Item] = []
    private(set) var known = KnownCompanies()
    private(set) var runs: [OutboundRunRecord] = []

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let task: String
    @ObservationIgnored private let openSession: () throws -> WebSession

    init(store: Store, capture: CaptureService, task: String, openSession: @escaping () throws -> WebSession) {
        self.store = store
        self.capture = capture
        self.task = task
        self.openSession = openSession
    }

    let scope = ""
    var isReady: Bool { capture.policy.isEnabled(.web) }
    var standing: SourceStanding { isReady ? .ready : .off }

    func refresh(on day: WorkDay) throws {
        let today = WorkDay(containing: store.clock())
        items = try store.queries.items(of: task, since: today.adding(days: -Self.listedDays))
        known = try store.queries.knownCompanies(task: task)
        runs = try store.queries.outboundRuns(task: task)
    }

    /// Candidates are found by `find`, not read by the day.
    func evidence(on day: WorkDay) throws -> EvidenceSet { EvidenceSet(lines: []) }

    /// Startups are found by search, not by the day: one run writes queries, searches, fetches and reads the pages.
    /// The candidates belong to the machine whose spec is given.
    func ownRead(spec: HelperSpec, model: () throws -> RecordedModel) async throws -> (kept: Int, dropped: Int)? {
        let model = try model()
        let record = try await OutboundRun(session: try openSession(), model: model, spec: spec).run()
        return (record.kept, record.found - record.kept)
    }

    func notAFit(_ item: Item, reason: String) throws { try store.rejectCandidate(item, reason: reason) }

    func snooze(_ item: Item, days: Int) throws {
        try store.snoozeCandidate(item, until: WorkDay(containing: store.clock()).adding(days: days))
    }

    func accepted(_ item: Item, asDeal deal: String) throws { try store.acceptCandidate(item, asDeal: deal) }
}
