import Foundation

public enum ClaimType: String, Codable, CaseIterable, Sendable {
    case marketSize = "market_size"
    case revenueOrTraction = "revenue_or_traction"
    case teamBackground = "team_background"
    case funding
    case customers
    case other
}

public struct Claim: Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var deal: String
    public var text: String
    public var type: ClaimType
    public var value: String
    public var quote: String
    public var line: Int64

    public init(
        id: Int64? = nil, deal: String, text: String, type: ClaimType, value: String, quote: String, line: Int64
    ) {
        self.id = id
        self.deal = deal
        self.text = text
        self.type = type
        self.value = value
        self.quote = quote
        self.line = line
    }

    static let task = "vc.claims"
    static let dealField = "deal"
}

public enum ClaimVerdict: String, Codable, CaseIterable, Sendable {
    case supported, contradicted
    case notFound = "not_found"
    case unclear

    var needsQuote: Bool { self == .supported || self == .contradicted }

    public var title: String {
        switch self {
        case .supported: "Supported"
        case .contradicted: "Contradicted"
        case .notFound: "No public evidence"
        case .unclear: "Unclear"
        }
    }
}

public struct ClaimCheck: Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var claim: Int64
    public var deal: String
    public var claimText: String
    public var verdict: ClaimVerdict
    public var quote: String
    public var url: String
    public var checkedAt: Date
    public var verdictMark: Mark = .proposed
    public var quoteMark: Mark = .proposed

    public init(
        id: Int64? = nil, claim: Int64, deal: String, claimText: String, verdict: ClaimVerdict, quote: String = "",
        url: String = "", checkedAt: Date
    ) {
        self.id = id
        self.claim = claim
        self.deal = deal
        self.claimText = claimText
        self.verdict = verdict
        self.quote = quote
        self.url = url
        self.checkedAt = checkedAt
    }
}
