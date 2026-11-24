import Foundation

/// A deal the investor decided on in the past, with their own call. It is the held-out set: it is never an `Item`, so
/// no example, no brief edit and no improver can see it. It only judges the criteria (research 40).
public struct PastDeal: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var company: String
    public var text: String
    /// Where the deck was, kept for the investor's reference; Workbench does not fetch it.
    public var url: String?
    /// The name of one of the criteria's levels.
    public var call: String
    /// The rule readings of the latest model reading; nil until the deal is read.
    public var reading: [String: String]?

    public init(
        id: String = UUID().uuidString, company: String, text: String, url: String? = nil, call: String,
        reading: [String: String]? = nil
    ) {
        self.id = id
        self.company = company
        self.text = text
        self.url = url
        self.call = call
        self.reading = reading
    }
}

/// How often code's call, from the model's rule readings, matches the investor's own call on the held-out deals.
/// Every number here is on the held-out set; none is on dev data.
public struct AgreementReport: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public var deal: PastDeal
        public var triage: Triage
        public var id: String { deal.id }
        public var agrees: Bool { triage.rating == deal.call }
        /// A rule was added or reworded after the deal was read: its result is unknown until a new reading.
        public var needsReading: Bool { triage.results.contains { !$0.isRead } }
    }

    /// Always the held-out set: past deals are never used to tune.
    public let split = EvalSplit.heldOut
    public var rows: [Row]
    public let levels: [Level]
    /// Deals not read yet: left out of every number.
    public var unread: Int

    public init(deals: [PastDeal], criteria: Criteria) {
        rows = deals.compactMap { deal in
            deal.reading.map { Row(deal: deal, triage: criteria.triage($0)) }
        }
        levels = criteria.levels
        unread = deals.count - rows.count
    }

    public var total: Int { rows.count }
    public var agreed: Int { rows.filter(\.agrees).count }
    public var rate: Double? { total == 0 ? nil : Double(agreed) / Double(total) }

    /// Deals the investor called the best level that the criteria rated the lowest: the miss that costs most.
    public var topMissed: Int {
        guard let best = levels.first, let lowest = levels.last, best != lowest else { return 0 }
        return count(called: best.name, rated: lowest.name)
    }
    public var calledTop: Int { rows.filter { $0.deal.call == levels.first?.name }.count }
    public var needingReading: Int { rows.filter(\.needsReading).count }
    public var needingReview: Int { rows.filter(\.triage.needsReview).count }

    public func count(called call: String, rated rating: String) -> Int {
        rows.filter { $0.deal.call == call && $0.triage.rating == rating }.count
    }

    /// The agreement rate the held-out deals support with 90 percent confidence: an exact binomial (Clopper-Pearson)
    /// bound.
    public var agreementFloor: Double? {
        total == 0 ? nil : 1 - ClopperPearson.upperBound(wrong: total - agreed, of: total)
    }

    /// The most top-missed deals the held-out calls support among deals the investor calls the best level, at 90 percent.
    public var topMissedCeiling: Double? {
        calledTop == 0 ? nil : ClopperPearson.upperBound(wrong: topMissed, of: calledTop)
    }
}
