import Foundation

/// What the investor typed about a company they follow: its aliases and domain. With `deal` set it adds to that
/// deal's company (the deal's title is its name); without, it is a company added by hand.
public struct WatchEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var aliases: [String]
    public var domain: String?
    public var deal: String?
    /// For a company added by hand: nil means portfolio.
    public var status: WatchedCompany.Status?

    public init(
        id: String = UUID().uuidString, name: String = "", aliases: [String] = [], domain: String? = nil,
        deal: String? = nil, status: WatchedCompany.Status? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.domain = domain
        self.deal = deal
        self.status = status
    }
}

/// A company the investor follows in the news: a deal they invested in or passed on, or one added by hand.
public struct WatchedCompany: Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable {
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

    /// The words that offer the company to the news reader (see `CompanyName.offerTerms`).
    var offerTerms: [String] { CompanyName.offerTerms(name: name, aliases: aliases) }

    /// The companies to follow: deals in a won stage (portfolio) and in a watch stage (passed), then those added by hand. A
    /// company whose domain is already followed is not listed twice. Two companies with the same name and no shared
    /// domain stay two: the model chooses between them for an article that names both.
    public static func list(deals: [WorkObject], entries: [WatchEntry]) -> [WatchedCompany] {
        let extras = Dictionary(entries.compactMap { entry in entry.deal.map { ($0, entry) } }) { first, _ in first }
        let fromDeals = deals.compactMap { deal -> WatchedCompany? in
            let status: Status? =
                deal.meanings.contains(.won) ? .portfolio : deal.meanings.contains(.watch) ? .passed : nil
            return status.map {
                WatchedCompany(
                    id: deal.id, name: deal.name, aliases: extras[deal.id]?.aliases ?? [],
                    domain: extras[deal.id]?.domain, status: $0, isDeal: true)
            }
        }
        let byHand = entries.filter { $0.deal == nil && $0.name.cleaned != nil }.map {
            WatchedCompany(
                id: $0.id, name: $0.name, aliases: $0.aliases, domain: $0.domain, status: $0.status ?? .portfolio,
                isDeal: false)
        }
        var domains: Set<String> = []
        return (fromDeals + byHand).filter { company in company.domain.map { domains.insert($0).inserted } ?? true }
    }
}

extension WatchedCompany {
    /// The companies of deals that stand in a stage of meaning won (portfolio) or watch (passed), by what the stage
    /// means, never by its label.
    public static func inStages(of deals: [WorkObject]) -> [WatchedCompany] { list(deals: deals, entries: []) }
}

extension Store {
    static let watchEntriesKey = "vc.watch.entries"

    public func saveWatchEntries(_ entries: [WatchEntry]) throws {
        try saveState(try Coding.json(entries), forKey: Self.watchEntriesKey)
    }

    /// Follows a company the person names, with its web address when they give one. A name already followed is kept
    /// once.
    public func follow(_ name: String, domain: String?, status: WatchedCompany.Status) throws {
        guard let name = name.cleaned else { return }
        let entries = try queries.watchEntries()
        guard !entries.contains(where: { CompanyName.normal($0.name) == CompanyName.normal(name) }) else { return }
        try saveWatchEntries(
            entries + [WatchEntry(name: name, domain: domain.flatMap(CompanyName.domain), status: status)])
    }

    /// Pins the companies of deals that stand in a won or watch stage, so the person can add their web addresses.
    /// Returns how many were new.
    @discardableResult
    public func followDeals(_ deals: [WorkObject]) throws -> Int {
        let entries = try queries.watchEntries()
        let known = Set(entries.compactMap(\.deal))
        let fresh = WatchedCompany.inStages(of: deals).filter { !known.contains($0.id) }
        try saveWatchEntries(entries + fresh.map { WatchEntry(deal: $0.id) })
        return fresh.count
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
