import Foundation
import LocalSources
import Observation
import WorkbenchCore

@Observable
final class PageSource: MachineSource {
    private(set) var sites: [String]
    private(set) var pageReading: (pages: [Activity], leftOut: Int) = ([], 0)

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let sitesKey: StateKey<[String]>

    init(store: Store, task: String) throws {
        self.store = store
        sitesKey = MachineKey.sites(task)
        sites = try sitesKey.load(from: store) ?? []
    }

    let scope = ""
    var isReady: Bool { !sites.isEmpty }

    func choose(_ typed: String) throws {
        let chosen = Array(
            Set(typed.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { WebPage.site(String($0)) })
        ).sorted()
        try sitesKey.save(chosen, to: store)
        sites = chosen
    }

    func refresh(on day: WorkDay) throws { pageReading = try reading(on: day) }

    func evidence(on day: WorkDay) throws -> EvidenceSet {
        EvidenceSet(lines: try reading(on: day).pages.compactMap(\.pageEvidence))
    }

    private func reading(on day: WorkDay) throws -> (pages: [Activity], leftOut: Int) {
        WebPage.reading(try store.queries.activities(from: day.start, to: day.end), sites: sites)
    }
}
