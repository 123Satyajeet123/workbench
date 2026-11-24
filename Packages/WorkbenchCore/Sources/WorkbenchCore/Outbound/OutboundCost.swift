import Foundation

/// What one outbound run costs, in US dollars: the searches at the provider's price, and the model calls at list
/// price. On a subscription the model share is what the calls would have cost, not what was billed.
public struct OutboundCost: Codable, Sendable, Equatable {
    public var searches: Int
    public var pages: Int
    public var searchUSD: Double
    public var modelUSD: Double

    public var totalUSD: Double { searchUSD + modelUSD }

    /// Dollars for one search. Claude web search: the first guess is the mean cost per search measured on 30 dev
    /// claims at effort "low", not a price. Brave: 5 USD per 1,000 (provider page, research 39). Exa: 4 to 12 USD per 1,000
    /// depending on the search type; the middle of that range, not measured.
    public static func searchUSD(_ provider: SearchProviderKind) -> Double {
        switch provider {
        case .model: RunSettings.standard.modelSearchUSD
        case .brave: RunSettings.standard.braveSearchUSD
        case .exa: RunSettings.standard.exaSearchUSD
        }
    }

    /// The cost to expect before a run: a query writer call is not counted, a page read is.
    public static func estimate(
        provider: SearchProviderKind, searches: Int, pages: Int,
        perPageUSD: Double = RunSettings.standard.firstGuessPerPageUSD
    ) -> OutboundCost {
        OutboundCost(
            searches: searches, pages: pages, searchUSD: Double(searches) * searchUSD(provider),
            modelUSD: Double(pages) * perPageUSD)
    }

    /// What the next run is expected to cost: the queries the searchable rules need, a full set of pages, and the
    /// last run's measured cost for a page when there was one.
    public static func nextRun(criteria: Criteria, provider: SearchProviderKind, last: OutboundCost?) -> OutboundCost {
        estimate(
            provider: provider,
            searches: OutboundQueries.searchable(criteria).count * RunSettings.standard.typicalQueriesPerRule,
            pages: RunSettings.standard.pagesPerRun,
            perPageUSD: last?.perPageUSD ?? RunSettings.standard.firstGuessPerPageUSD)
    }

    /// The share of the model cost for each page, from a run that was measured; nil when it read no page.
    public var perPageUSD: Double? { pages == 0 ? nil : modelUSD / Double(pages) }
}
