import Foundation
import LocalSources
import Observation
import WorkbenchCore

/// Pages the founder saw on the sites a machine's owner named. Naming the sites is the consent: no other site's text
/// is read. The text comes from the browser extension, kept only under the Screen text switch.
@Observable
final class PageSource: MachineSource {
    private(set) var sites: [String]
    /// The day's page texts on the sites, and how many were past the budget, as last refreshed.
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

    /// Sites as the founder typed them, separated by commas or spaces. Anything that is not a site is left out.
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
