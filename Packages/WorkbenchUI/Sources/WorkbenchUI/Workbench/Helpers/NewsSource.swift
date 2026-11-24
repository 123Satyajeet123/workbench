import CaptureService
import Foundation
import Observation
import WebResearch
import WorkbenchCore

/// The news feeds, read for the companies the investor follows. The switch is the web research consent: with it off
/// the machine is not ready and nothing is fetched. A check goes through `FeedSession`, which opens only while the
/// consent is on. The followed companies are the Invested and Rejected deals plus the ones typed here.
@Observable
final class NewsSource: MachineSource {
    private(set) var companies: [WatchedCompany] = []
    private(set) var articlesKept = 0

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let capture: CaptureService
    @ObservationIgnored private let makeFetcher: (CaptureGrant) -> any FeedFetching

    init(
        store: Store, capture: CaptureService,
        makeFetcher: @escaping (CaptureGrant) -> any FeedFetching = { FeedFetcher(grant: $0) }
    ) {
        self.store = store
        self.capture = capture
        self.makeFetcher = makeFetcher
    }

    let scope = ""
    var isReady: Bool { capture.policy.isEnabled(.web) }
    var standing: SourceStanding { isReady ? .ready : .off }
    var context: [String: [String]] { [NewsSignals.companies: companies.map(\.name)] }

    func refresh(on day: WorkDay) throws {
        companies = try store.queries.watchedCompanies()
        articlesKept = try store.queries.articleCount()
    }

    /// The news is read one article at a time by `check`, not by the day.
    func evidence(on day: WorkDay) throws -> EvidenceSet { EvidenceSet(lines: []) }

    /// The news is checked, not read by the day: one check fetches the feeds and reads each matched article.
    func ownRead(spec: HelperSpec, model: () throws -> RecordedModel) async throws -> (kept: Int, dropped: Int)? {
        let report = try await check(with: model(), spec: spec)
        return (report.kept, report.dropped)
    }

    /// Fetches the feeds, matches the articles and reads each matched one with `model`. The facts belong to the
    /// machine whose spec is given.
    func check(with model: RecordedModel, spec: HelperSpec) async throws -> NewsCheck.Report {
        let session = try FeedSession.open(store: store, feeds: spec.feeds ?? [], make: makeFetcher)
        return try await NewsCheck(session: session, model: model, spec: spec).run(
            watching: try store.queries.watchedCompanies())
    }

    /// Adds a company by hand. Aliases are separated by commas; the domain may be typed as an address.
    func add(name: String, aliases: String, domain: String) throws {
        guard let name = name.cleaned else { return }
        try save(try store.queries.watchEntries() + [Self.entry(name: name, aliases: aliases, domain: domain)])
    }

    /// The aliases and domain the investor confirms for a company, a deal's or one typed by hand.
    func setDetails(of company: WatchedCompany, aliases: String, domain: String) throws {
        var entries = try store.queries.watchEntries()
        let confirmed = Self.entry(name: company.name, aliases: aliases, domain: domain)
        if let index = entries.firstIndex(where: { $0.id == company.id || $0.deal == company.id }) {
            entries[index].aliases = confirmed.aliases
            entries[index].domain = confirmed.domain
        } else {
            entries.append(
                WatchEntry(aliases: confirmed.aliases, domain: confirmed.domain, deal: company.id))
        }
        try save(entries)
    }

    /// Stops following a company typed by hand. A deal is followed while it is Invested or Rejected.
    func remove(_ company: WatchedCompany) throws {
        guard !company.isDeal else { return }
        try save(try store.queries.watchEntries().filter { $0.id != company.id })
    }

    private func save(_ entries: [WatchEntry]) throws {
        try store.saveWatchEntries(entries)
        try refresh(on: WorkDay(containing: store.clock()))
    }

    private static func entry(name: String, aliases: String, domain: String) -> WatchEntry {
        WatchEntry(
            name: name, aliases: aliases.split(separator: ",").compactMap { String($0).cleaned },
            domain: CompanyName.domain(domain))
    }
}
