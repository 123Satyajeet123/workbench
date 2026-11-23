import Foundation
import Observation
import WorkbenchCore

/// The founder's screen sessions, from the lines the capture service kept in the evidence store.
@Observable
final class ScreenSource: MachineSource {
    /// The sessions of the day last refreshed.
    private(set) var sessions: [ScreenSession] = []

    @ObservationIgnored private let store: Store

    init(store: Store) { self.store = store }

    let scope = ""
    let isReady = true

    func refresh(on day: WorkDay) throws { sessions = try sessions(on: day) }

    func evidence(on day: WorkDay) throws -> EvidenceSet {
        EvidenceSet(lines: try sessions(on: day).map(\.evidence))
    }

    private func sessions(on day: WorkDay) throws -> [ScreenSession] {
        try store.queries.screenSessions(from: day.start, to: day.end)
    }
}
