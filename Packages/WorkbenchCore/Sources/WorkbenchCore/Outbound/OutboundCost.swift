import Foundation

/// What one outbound run costs, in US dollars: the searches at the provider's price, and the model calls at list
/// price. On a subscription the model share is what the calls would have cost, not what was billed.
public struct OutboundCost: Codable, Sendable, Equatable {
    public var searches: Int
    public var pages: Int
    public var searchUSD: Double
    public var modelUSD: Double

    public var totalUSD: Double { searchUSD + modelUSD }

    /// Dollars for one search. Brave: 5 USD per 1,000 (provider page, research 39). Exa: 4 to 12 USD per 1,000
    /// depending on the search type; the middle of that range, not measured.
    public static func searchUSD(_ provider: SearchProviderKind) -> Double {
        switch provider {
        case .brave: 0.005
        case .exa: 0.008
        }
    }

    /// Dollars of model calls for one page read before any run has measured it. A guess for the first estimate only;
    /// later estimates use the average of the runs the store holds.
    public static let firstGuessPerPageUSD = 0.02

    /// The cost to expect before a run: a query writer call is not counted, a page read is.
    public static func estimate(
        provider: SearchProviderKind, searches: Int, pages: Int, perPageUSD: Double = firstGuessPerPageUSD
    ) -> OutboundCost {
        OutboundCost(
            searches: searches, pages: pages, searchUSD: Double(searches) * searchUSD(provider),
            modelUSD: Double(pages) * perPageUSD)
    }

    /// Queries a rule gets on average: the model is asked for three to five.
    static let typicalQueriesPerRule = 4

    /// What the next run is expected to cost: the queries the searchable rules need, a full set of pages, and the
    /// last run's measured cost for a page when there was one.
    public static func nextRun(criteria: Criteria, provider: SearchProviderKind, last: OutboundCost?) -> OutboundCost {
        estimate(
            provider: provider, searches: OutboundQueries.searchable(criteria).count * typicalQueriesPerRule,
            pages: Outbound.maxPages, perPageUSD: last?.perPageUSD ?? firstGuessPerPageUSD)
    }

    /// The share of the model cost for each page, from a run that was measured; nil when it read no page.
    public var perPageUSD: Double? { pages == 0 ? nil : modelUSD / Double(pages) }
}
