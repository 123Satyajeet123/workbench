import Foundation

public struct PastDeal: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var company: String
    public var text: String
    public var url: String?
    public var call: Rating
    public var reading: [String: String]?

    public init(
        id: String = UUID().uuidString, company: String, text: String, url: String? = nil, call: Rating,
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

public struct AgreementReport: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public var deal: PastDeal
        public var triage: Triage
        public var id: String { deal.id }
        public var agrees: Bool { triage.rating == deal.call }
        public var needsReading: Bool { triage.results.contains { !$0.isRead } }
    }

    public let split = EvalSplit.heldOut
    public var rows: [Row]
    public var unread: Int

    public init(deals: [PastDeal], criteria: Criteria) {
        rows = deals.compactMap { deal in
            deal.reading.map { Row(deal: deal, triage: criteria.triage($0)) }
        }
        unread = deals.count - rows.count
    }

    public var total: Int { rows.count }
    public var agreed: Int { rows.filter(\.agrees).count }
    public var rate: Double? { total == 0 ? nil : Double(agreed) / Double(total) }

    public var hotMissed: Int { count(called: .hot, rated: .cold) }
    public var calledHot: Int { rows.filter { $0.deal.call == .hot }.count }
    public var needingReading: Int { rows.filter(\.needsReading).count }
    public var needingReview: Int { rows.filter(\.triage.needsReview).count }

    public func count(called call: Rating, rated rating: Rating) -> Int {
        rows.filter { $0.deal.call == call && $0.triage.rating == rating }.count
    }

    public var agreementFloor: Double? {
        total == 0 ? nil : 1 - Certificate.upperBound(wrong: total - agreed, of: total)
    }

    public var hotMissedCeiling: Double? {
        calledHot == 0 ? nil : Certificate.upperBound(wrong: hotMissed, of: calledHot)
    }
}
