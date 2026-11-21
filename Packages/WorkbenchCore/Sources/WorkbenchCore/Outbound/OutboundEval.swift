import Foundation

/// Past deals with the investor's own calls, and the pages saved for them. A deal the investor called hot or warm is
/// one they accepted; cold is one they turned down. `split` is mandatory and says whether every number made from it is
/// dev or held-out.
public struct OutboundFixture: Decodable, Sendable {
    public struct Page: Decodable, Sendable {
        public var url: String
        public var text: String

        public init(url: String, text: String) {
            self.url = url
            self.text = text
        }
    }

    /// The candidates a model gave for one page, saved so the eval runs with no model: each is the fields of an item
    /// (company, domain, sector, quote, and the answer and quote of each rule by its id).
    public struct Saved: Decodable, Sendable {
        public var url: String
        public var candidates: [[String: String]]

        public init(url: String, candidates: [[String: String]]) {
            self.url = url
            self.candidates = candidates
        }
    }

    public var split: String
    public var criteria: Criteria
    /// Each deal's `url` and `text` are the page saved for it; `company` and `call` are the investor's.
    public var deals: [PastDeal]
    /// Pages with no deal behind them: what the search finds besides the deals.
    public var pages: [Page] = []
    public var saved: [Saved]
    /// Searches the run that found these pages sent, and the provider, for the cost.
    public var queries: Int = 0
    public var provider: SearchProviderKind = .brave

    public init(
        split: String, criteria: Criteria, deals: [PastDeal], pages: [Page] = [], saved: [Saved], queries: Int = 0,
        provider: SearchProviderKind = .brave
    ) {
        self.split = split
        self.criteria = criteria
        self.deals = deals
        self.pages = pages
        self.saved = saved
        self.queries = queries
        self.provider = provider
    }

    /// `pages`, `queries` and `provider` may be left out of the file.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        split = try values.decode(String.self, forKey: .split)
        criteria = try values.decode(Criteria.self, forKey: .criteria)
        deals = try values.decode([PastDeal].self, forKey: .deals)
        pages = try values.decodeIfPresent([Page].self, forKey: .pages) ?? []
        saved = try values.decode([Saved].self, forKey: .saved)
        queries = try values.decodeIfPresent(Int.self, forKey: .queries) ?? 0
        provider = try values.decodeIfPresent(SearchProviderKind.self, forKey: .provider) ?? .brave
    }

    private enum CodingKeys: String, CodingKey {
        case split, criteria, deals, pages, saved, queries, provider
    }

    /// Every page of the fixture, the deals' first.
    var allPages: [FetchedPage] {
        let dealPages = deals.compactMap { deal in
            deal.url.flatMap(URL.init(string:)).map { FetchedPage(url: $0, text: deal.text) }
        }
        return dealPages
            + pages.compactMap { page in URL(string: page.url).map { FetchedPage(url: $0, text: page.text) } }
    }
}

/// The outbound eval, offline: the real reader, name check, rating and ranking run over saved pages with a saved
/// model reply for each. It measures what the pipeline does with the pages; a live model's recall needs a live run.
public enum OutboundEval {
    public static let recallDepth = 100
    public static let precisionDepth = 20

    public struct Report: Sendable, Equatable {
        public var split: EvalSplit
        public var candidates: Int
        public var accepted: Int
        /// Accepted deals among the first `recallDepth` candidates.
        public var acceptedFound: Int
        /// The first `precisionDepth` candidates by the investor's calls.
        public var topRight: Int
        public var topWrong: Int
        public var topUnmarked: Int
        public var cost: OutboundCost

        public var topCount: Int { topRight + topWrong + topUnmarked }
        public var recall: Double? { accepted == 0 ? nil : Double(acceptedFound) / Double(accepted) }
        /// Right among the top candidates; one with no call counts as not right.
        public var precision: Double? { topCount == 0 ? nil : Double(topRight) / Double(topCount) }
        public var costPerAcceptedLead: Double? { acceptedFound == 0 ? nil : cost.totalUSD / Double(acceptedFound) }

        public var label: String { split == .dev ? "dev" : "held-out" }
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case unlabelled

        public var errorDescription: String? { "The fixture's split must be \"dev\" or \"held_out\"." }
    }

    public static func run(_ fixture: OutboundFixture, model: any StructuredModel, store: Store) async throws -> Report
    {
        guard let split = EvalSplit(rawValue: fixture.split) else { throw Failure.unlabelled }
        var spec = HelperSpec.outbound
        spec.criteria = fixture.criteria
        let reader = OutboundReader(model: RecordedModel(model, store: store), spec: spec)
        let pages = fixture.allPages
        var found: [Item] = []
        for page in pages { found += try await reader.read(page, fetched: store.clock()).items }
        let ranked = OutboundReview.rank(
            OutboundReview.bestOfEach(found, criteria: fixture.criteria, known: KnownCompanies()),
            criteria: fixture.criteria)
        return report(split, ranked: ranked, fixture: fixture, pages: pages.count)
    }

    private static func report(_ split: EvalSplit, ranked: [OutboundCandidate], fixture: OutboundFixture, pages: Int)
        -> Report
    {
        let accepted = fixture.deals.filter { $0.call != .cold }
        func known(_ deals: [PastDeal]) -> KnownCompanies {
            var known = KnownCompanies()
            for deal in deals { known.add(name: deal.company) }
            return known
        }
        let (right, wrong) = (known(accepted), known(fixture.deals.filter { $0.call == .cold }))
        let top = ranked.prefix(precisionDepth)
        var deep = KnownCompanies()
        for candidate in ranked.prefix(recallDepth) { deep.add(name: candidate.company, domain: candidate.domain) }
        return Report(
            split: split, candidates: ranked.count, accepted: accepted.count,
            acceptedFound: accepted.filter { deal in deep.contains(name: deal.company, domain: nil) }.count,
            topRight: top.filter { right.contains(name: $0.company, domain: nil) }.count,
            topWrong: top.filter { wrong.contains(name: $0.company, domain: nil) }.count,
            topUnmarked: top.filter {
                !right.contains(name: $0.company, domain: nil) && !wrong.contains(name: $0.company, domain: nil)
            }.count,
            cost: .estimate(provider: fixture.provider, searches: fixture.queries, pages: pages))
    }
}
