import Foundation

extension WorkObject {
    public static let invested = "Invested"
    public static let rejected = "Rejected"
}

/// What the investor typed about a company they follow: its aliases and domain. With `deal` set it adds to that
/// deal's company (the deal's title is its name); without, it is a company added by hand.
public struct WatchEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var domain: String?
    public var deal: String?

    public init(
        id: String = UUID().uuidString, name: String = "", aliases: [String] = [], domain: String? = nil,
        deal: String? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.domain = domain
        self.deal = deal
    }
}

/// A company the investor follows in the news: a deal they invested in or passed on, or one added by hand.
public struct WatchedCompany: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable {
        case portfolio, passed
    }

    /// The deal's id, or the id of the entry typed by hand. A signal keeps it as `company_id`.
    public var id: String
    public var name: String
    public var aliases: [String]
    public var domain: String?
    public var status: Status
    public var isDeal: Bool

    /// The words that name the company in news, normalised (see `CompanyName.terms`).
    public var terms: [String] { CompanyName.terms(name: name, aliases: aliases) }

    /// The companies to follow: deals in Invested (portfolio) and in Rejected (passed), then those added by hand. A
    /// company whose domain is already followed is not listed twice. Two companies with the same name and no shared
    /// domain stay two: the model chooses between them for an article that names both.
    public static func list(deals: [WorkObject], entries: [WatchEntry]) -> [WatchedCompany] {
        let extras = Dictionary(entries.compactMap { entry in entry.deal.map { ($0, entry) } }) { first, _ in first }
        let fromDeals = deals.compactMap { deal -> WatchedCompany? in
            let status: Status? =
                deal.stages.contains(WorkObject.invested)
                ? .portfolio : deal.stages.contains(WorkObject.rejected) ? .passed : nil
            return status.map {
                WatchedCompany(
                    id: deal.id, name: deal.title, aliases: extras[deal.id]?.aliases ?? [],
                    domain: extras[deal.id]?.domain, status: $0, isDeal: true)
            }
        }
        let byHand = entries.filter { $0.deal == nil && $0.name.cleaned != nil }.map {
            WatchedCompany(
                id: $0.id, name: $0.name, aliases: $0.aliases, domain: $0.domain, status: .portfolio, isDeal: false)
        }
        var domains: Set<String> = []
        return (fromDeals + byHand).filter { company in company.domain.map { domains.insert($0).inserted } ?? true }
    }
}

extension Store {
    static let watchEntriesKey = "vc.watch.entries"

    public func saveWatchEntries(_ entries: [WatchEntry]) throws {
        try saveState(try Coding.json(entries), forKey: Self.watchEntriesKey)
    }
}

extension Queries {
    public func watchEntries() throws -> [WatchEntry] {
        try state(forKey: Store.watchEntriesKey).flatMap { try? Coding.value([WatchEntry].self, from: $0) } ?? []
    }

    /// The deals as the founder's own events fold them, with the companies to follow among them.
    public func watchedCompanies() throws -> [WatchedCompany] {
        let deals = WorkObject.fold(try workEvents(), viewer: "").filter { $0.kind == "deal" && !$0.archived }
        return WatchedCompany.list(deals: deals, entries: try watchEntries())
    }
}
