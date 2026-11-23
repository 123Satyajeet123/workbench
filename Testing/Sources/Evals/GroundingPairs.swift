import CryptoKit
import Foundation
import WorkbenchCore

/// One claim and one premise, with the label the construction gives it. Every pair is dev: it comes from the dev set
/// (`data/vc/dev`) and from code that edits it.
public struct GroundingPair: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// The claim with the true value, against the quote that states it.
        case supported
        /// The dev set's own claim, with its planted wrong value.
        case planted
        /// The supported claim with an amount changed by code.
        case amount
        /// The supported claim with a year moved by code.
        case year
        /// The supported claim with a name replaced by code.
        case name
        /// The supported claim against the quote of another company.
        case otherCompany = "other_company"
    }

    public var id: String
    public var company: String
    public var kind: Kind
    /// Whether the premise supports the claim, by construction.
    public var supported: Bool { kind == .supported }
    public var claim: String
    public var premise: String

    public init(id: String, company: String, kind: Kind, claim: String, premise: String) {
        self.id = id
        self.company = company
        self.kind = kind
        self.claim = claim
        self.premise = premise
    }
}

public enum GroundingPairs {
    /// The pairs of the dev claims.
    public static func make(from claims: [DevClaim]) -> [GroundingPair] {
        var pairs: [GroundingPair] = []
        for claim in claims {
            let other = claims.first { $0.company != claim.company && $0.id != claim.id }
            let edits = edited(claim)
            pairs.append(
                GroundingPair(
                    id: "\(claim.id)-planted", company: claim.company, kind: .planted, claim: claim.claimText,
                    premise: claim.truthQuote))
            guard let supported = edits.supported else { continue }
            pairs.append(
                GroundingPair(
                    id: "\(claim.id)-supported", company: claim.company, kind: .supported, claim: supported,
                    premise: claim.truthQuote))
            for (kind, text) in edits.negatives {
                pairs.append(
                    GroundingPair(
                        id: "\(claim.id)-\(kind.rawValue)", company: claim.company, kind: kind, claim: text,
                        premise: claim.truthQuote))
            }
            if let other {
                pairs.append(
                    GroundingPair(
                        id: "\(claim.id)-other", company: claim.company, kind: .otherCompany, claim: supported,
                        premise: other.truthQuote))
            }
        }
        return pairs
    }

    /// The supported claim (the planted value replaced by the true one), and the negatives code makes from it.
    static func edited(_ claim: DevClaim) -> (supported: String?, negatives: [(GroundingPair.Kind, String)]) {
        guard claim.claimText.contains(claim.plantedWrongValue) else { return (nil, []) }
        let supported = claim.claimText.replacingOccurrences(of: claim.plantedWrongValue, with: claim.trueValue)
        let source = ProductClaim(text: supported, cites: [])
        let made: [(GroundingPair.Kind, CatchKind)] = [(.amount, .amount), (.year, .year), (.name, .name)]
        return (
            supported, made.compactMap { pair in CatchClaim.make(from: source, kind: pair.1).map { (pair.0, $0.text) } }
        )
    }

    /// The pairs with each premise made longer by the page around its quote, where the cache has the page.
    public static func withContext(_ pairs: [GroundingPair], claims: [DevClaim], context: (DevClaim) -> String?)
        -> [GroundingPair]
    {
        pairs.compactMap { pair in
            guard let claim = claims.first(where: { pair.id.hasPrefix($0.id + "-") }), pair.kind != .otherCompany,
                let page = context(claim)
            else { return nil }
            var longer = pair
            longer.premise = page
            return longer
        }
    }

    /// The half of the companies by the hash of their name: the first half chooses a threshold, the second reports.
    public static func chooseHalf(_ company: String, among companies: [String]) -> Bool {
        let ranked = companies.sorted { digest($0) < digest($1) }
        return (ranked.firstIndex(of: company) ?? 0) < ranked.count / 2
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
