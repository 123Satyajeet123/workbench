import Foundation
import Observation
import WorkbenchCore

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
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    @ObservationIgnored private let store: Store

    init(store: Store) {
        self.store = store
        refresh()
    }

    func refresh() {
        problems.attempt("read the runs", clearing: true) {
            let now = store.clock()
            let today = Calendar.current.startOfDay(for: now)
            runs = try store.queries.runs()
            quality = try store.queries.quality()
            meter = Meter(
                today: try store.queries.usage(since: today),
                week: try store.queries.usage(since: today.addingTimeInterval(-6 * 86_400)),
                all: runs.compactMap(\.usage).reduce(Usage(), +))
        }
    }
}

extension Usage {
    var tokensText: String { tokens.formatted(.number.notation(.compactName)) }
    var costText: String { costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2))) }
}
