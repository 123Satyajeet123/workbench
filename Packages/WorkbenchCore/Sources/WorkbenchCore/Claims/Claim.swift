import Foundation
import Kernel

/// What a claim in a deck is about, as data in a machine's spec. `proof` says what counts as proof of a claim of this
/// type: it tells the model which source can settle it.
public struct ClaimType: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var label: String
    public var proof: String

    public init(id: String, label: String, proof: String) {
        self.id = id
        self.label = label
        self.proof = proof
    }
}

/// One thing a deck says that can be checked: its words, its type, the value it states, and where in the deck it said
/// so. The founder chooses which claims to check.
public struct Claim: Sendable, Equatable, Identifiable {
    /// Set when read from the store.
    public var id: Int64?
    public var deal: String
    public var text: String
    /// The id of one of the machine's claim types. An id the spec no longer lists is kept as it was stored.
    public var type: String
    /// The number, name or date the claim states, such as "$11 million".
    public var value: String
    /// Words copied from the deck line the claim came from.
    public var quote: String
    /// The mail part the quote is in.
    public var line: Int64
    /// Who may read the lines the claim rests on, as code computed it when the claim was read. Nil when not known:
    /// then no search query is built from the claim.
    public var label: Label?
    /// How far the lines the claim rests on may be trusted.
    public var authority: Authority
    /// The kind of source of the line the claim rests on. Nil when not known: the model calls that hold its words
    /// then count as holding data of an unknown kind.
    public var source: SourceKind?

    public init(
        id: Int64? = nil, deal: String, text: String, type: String, value: String, quote: String, line: Int64,
        label: Label? = nil, authority: Authority = .unknown, source: SourceKind? = nil
    ) {
        self.id = id
        self.deal = deal
        self.text = text
        self.type = type
        self.value = value
        self.quote = quote
        self.line = line
        self.label = label
        self.authority = authority
        self.source = source
    }

    /// The consent kinds a model call that holds this claim's words holds.
    var holding: Set<SourceKind> { source.map { [$0] } ?? [] }

    static let task = "vc.claims"
    static let dealField = "deal"
}

/// What a check found. "Not found" is no evidence either way: it is never "contradicted".
public enum ClaimVerdict: String, Codable, CaseIterable, Sendable {
    case supported, contradicted
    case notFound = "not_found"
    case unclear

    /// The verdicts that must rest on a quote from a fetched page.
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
    /// Set when read from the store.
    public var id: Int64?
    public var claim: Int64
    public var deal: String
    public var claimText: String
    public var verdict: ClaimVerdict
    /// Words found verbatim in the page at `url`; empty when the verdict rests on none.
    public var quote: String
    public var url: String
    public var checkedAt: Date
    /// The founder's mark: is the verdict right.
    public var verdictMark: Mark = .proposed
    /// The founder's mark: is the quote right.
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
