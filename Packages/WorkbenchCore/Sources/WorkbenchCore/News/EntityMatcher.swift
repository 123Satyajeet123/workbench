import Foundation

/// A company an article may be about, with the label the model sees: the name, made unique among the article's
/// candidates when two companies share it.
public struct Candidate: Sendable, Equatable {
    public var company: WatchedCompany
    public var label: String
}

/// Finds which followed companies an article may be about. Code only, and wide: the first words of a name or alias
/// appearing as whole words, or the company's domain appearing as an address. No fuzzy matching. The reader's one
/// call per article says which candidate the article is about, if any, and code checks the answer.
public enum EntityMatcher {
    public static func candidates(in article: NewsArticle, among watched: [WatchedCompany]) -> [Candidate] {
        let words = CompanyName.words(article.body)
        let domainHit = Set(
            watched.filter { company in company.domain.map { CompanyName.mentions(article.body, domain: $0) } ?? false }
                .map(\.id))
        let named = watched.filter { company in
            domainHit.contains(company.id) || company.offerTerms.contains { CompanyName.contains(words, term: $0) }
        }
        let kept = named.filter { company in
            domainHit.contains(company.id)
                || !named.contains { other in domainHit.contains(other.id) && shareName(company, other) }
        }
        return labelled(kept)
    }

    /// Two companies share a name when they have one normalised form in common.
    static func shareName(_ first: WatchedCompany, _ second: WatchedCompany) -> Bool {
        !Set(first.terms).isDisjoint(with: second.terms)
    }

    /// A unique label for each: the name, then the domain or status when a name repeats, then a number.
    static func labelled(_ companies: [WatchedCompany]) -> [Candidate] {
        let repeated = Dictionary(grouping: companies, by: { CompanyName.normal($0.name) }).filter { $1.count > 1 }
        var used: Set<String> = []
        return companies.map { company in
            var label = company.name
            if repeated[CompanyName.normal(company.name)] != nil {
                label += " (\(company.domain ?? company.status.rawValue))"
            }
            var number = 2
            let base = label
            while !used.insert(label).inserted {
                label = "\(base) #\(number)"
                number += 1
            }
            return Candidate(company: company, label: label)
        }
    }
}
