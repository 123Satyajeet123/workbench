import Foundation
import Observation
import WorkbenchCore

/// The founder's screen sessions, from the activity the capture service kept.
@Observable
final class ScreenSource: MachineSource {
    /// Activity this long before the day starts tells which window was open at its start.
    private static let lookBack: TimeInterval = 6 * 3600

    /// The window in front now is still growing: it waits until it closes, so a block never stops mid-task and a
    /// later reading never finds its line already read.
    static let stillOpen: TimeInterval = 60

    /// The sessions of the day last refreshed.
    private(set) var sessions: [ScreenSession] = []

    @ObservationIgnored private let store: Store

    init(store: Store) { self.store = store }

    let scope = ""
    let isReady = true

    func refresh(on day: WorkDay) throws { sessions = try sessions(on: day) }

    func evidence(on day: WorkDay) throws -> EvidenceSet {
        var sessions = try sessions(on: day)
        if let last = sessions.last, store.clock().timeIntervalSince(last.end) < Self.stillOpen {
            sessions.removeLast()
        }
        return EvidenceSet(lines: sessions.map(\.evidence))
    }

    private func sessions(on day: WorkDay) throws -> [ScreenSession] {
        let activity = try store.queries.activities(from: day.start.addingTimeInterval(-Self.lookBack), to: day.end)
        return Sessions.make(from: activity, start: day.start, end: min(day.end, store.clock()))
    }
}
