import Foundation
import Observation
import WorkbenchCore

/// Every model call and what it cost, and how well each prompt on each model did by the founder's marks.
@Observable
final class RunsModel {
    struct Meter: Equatable {
        var today = Usage()
        var week = Usage()
        var all = Usage()
    }

    private(set) var runs: [Run] = []
    private(set) var quality: [Quality] = []
    private(set) var meter = Meter()
    private(set) var problem: String?

    @ObservationIgnored private let store: Store

    init(store: Store) {
        self.store = store
        refresh()
    }

    func refresh() {
        do {
            let now = store.clock()
            let today = Calendar.current.startOfDay(for: now)
            runs = try store.queries.runs()
            quality = try store.queries.quality()
            meter = Meter(
                today: try store.queries.usage(since: today),
                week: try store.queries.usage(since: today.addingTimeInterval(-6 * 86_400)),
                all: runs.map(\.usage).reduce(Usage(), +))
            problem = nil
        } catch {
            problem = "Could not read the runs: \(error.localizedDescription)"
        }
    }
}

extension Usage {
    var tokensText: String { tokens.formatted(.number.notation(.compactName)) }
    var costText: String { costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2))) }
}
