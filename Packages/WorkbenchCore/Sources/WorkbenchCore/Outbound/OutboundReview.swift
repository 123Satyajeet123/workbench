import Foundation

/// A startup found on the web, with the call code made from its rule results. The call follows the criteria as they
/// are now (it is never stored), so an edit of the criteria re-ranks the list with no new reading.
public struct OutboundCandidate: Sendable, Equatable, Identifiable {
    public var item: Item
    public var triage: Triage

    public var id: Int64? { item.id }
    public var company: String { item["company"] }
    public var domain: String? { item["domain"].cleaned }
    public var sector: String? { item["sector"].cleaned }
    /// The page the startup was found on.
    public var url: URL? { URL(string: item[Outbound.urlField]) }
}

public enum OutboundReview {
    /// Candidates ranked by level, best first, then points, then name. The order is a pure function of the
    /// rule results, so the same readings always give the same list.
    public static func rank(_ items: [Item], criteria: Criteria) -> [OutboundCandidate] {
        return items.map { OutboundCandidate(item: $0, triage: criteria.triage($0.fields)) }
            .sorted { first, second in
                let (a, b) = (first.triage, second.triage)
                if a.place != b.place { return a.place < b.place }
                if a.points != b.points { return a.points > b.points }
                return first.company.comparable < second.company.comparable
            }
    }

    /// What the investor still has to review: candidates with no mark, not hidden or snoozed, and not already a deal
    /// or turned down since they were found.
    public static func list(
        _ items: [Item], criteria: Criteria, known: KnownCompanies, now: Date
    ) -> [OutboundCandidate] {
        rank(
            items.filter { item in
                item.state == .proposed && !item.isHidden(at: now)
                    && !known.contains(name: item["company"], domain: item["domain"])
            }, criteria: criteria)
    }

    /// One candidate for each startup: of several pages that name the same one, the best ranked stays.
    public static func bestOfEach(_ found: [Item], criteria: Criteria, known: KnownCompanies) -> [Item] {
        var seen = known
        var kept: [Item] = []
        for candidate in rank(found, criteria: criteria)
        where !seen.contains(name: candidate.company, domain: candidate.domain) {
            seen = seen.adding([candidate.item])
            kept.append(candidate.item)
        }
        return kept
    }
}
