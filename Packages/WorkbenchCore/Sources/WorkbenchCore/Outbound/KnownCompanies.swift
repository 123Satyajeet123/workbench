import Foundation

/// The companies the investor already has a say about: deals in any stage, companies they follow, startups they marked
/// "not a fit". A candidate that matches one is left out. Matching is code only, by the normalised name (`CompanyName`,
/// the one the news watch uses) or by domain; no fuzzy match.
public struct KnownCompanies: Sendable, Equatable {
    private var terms: Set<String> = []
    private var domains: Set<String> = []

    public init() {}

    public mutating func add(name: String, aliases: [String] = [], domain: String? = nil) {
        terms.formUnion(CompanyName.terms(name: name, aliases: aliases))
        if let domain = domain.flatMap(CompanyName.domain) { domains.insert(domain) }
    }

    public func contains(name: String, domain: String?) -> Bool {
        if let domain = domain.flatMap(CompanyName.domain), domains.contains(domain) { return true }
        return !terms.isDisjoint(with: CompanyName.terms(name: name, aliases: []))
    }

    /// Every deal, archived or not, with the aliases and domain the investor confirmed for it, the companies they
    /// follow by hand, and the startups they turned down.
    public init(deals: [WorkObject], entries: [WatchEntry], rejections: [Rejection]) {
        let extras = Dictionary(entries.compactMap { entry in entry.deal.map { ($0, entry) } }) { first, _ in first }
        for deal in deals where deal.kind == "deal" {
            add(name: deal.title, aliases: extras[deal.id]?.aliases ?? [], domain: extras[deal.id]?.domain)
        }
        for entry in entries where entry.deal == nil {
            add(name: entry.name, aliases: entry.aliases, domain: entry.domain)
        }
        for rejection in rejections { add(name: rejection.company, domain: rejection.domain) }
    }

    /// These companies and the candidates already kept, so a second page naming the same startup adds nothing.
    func adding(_ items: [Item]) -> KnownCompanies {
        var next = self
        for item in items { next.add(name: item["company"], domain: item["domain"]) }
        return next
    }
}
