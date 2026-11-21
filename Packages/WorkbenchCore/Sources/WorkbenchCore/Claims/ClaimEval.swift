import Foundation

/// One planted claim of the dev set (`data/vc/dev/claims.json`). Every number made from it is dev, never held-out.
public struct DevClaim: Decodable, Sendable {
    public var id: String
    public var company: String
    public var claimType: String
    public var claimText: String
    public var plantedWrongValue: String
    public var trueValue: String
    public var truthSourceUrl: String
    public var truthQuote: String

    enum CodingKeys: String, CodingKey {
        case id, company
        case claimType = "claim_type"
        case claimText = "claim_text"
        case plantedWrongValue = "planted_wrong_value"
        case trueValue = "true_value"
        case truthSourceUrl = "truth_source_url"
        case truthQuote = "truth_quote"
    }

    /// The claim type the dev set's own type belongs to.
    var type: ClaimType {
        switch claimType {
        case "round_size", "lead_investor": .funding
        case "incorporation_year", "founding_team_size": .teamBackground
        default: .other
        }
    }
}

/// An offline check of the claim pipeline over the dev set: no network and no model. The planted claim states a wrong
/// value and should come out `contradicted`; the same claim with the true value should come out `supported`.
public enum ClaimEval {
    public struct Case: Sendable {
        public var id: String
        public var claim: Claim
        public var page: FetchedPage
        public var expected: ClaimVerdict
    }

    public struct Report: Sendable, Equatable {
        public var planted = 0
        public var plantedContradicted = 0
        public var plantedSupported = 0
        public var trueClaims = 0
        public var trueSupported = 0
        /// A true claim called `contradicted`: the false alarm.
        public var trueContradicted = 0
        public var skipped: [String] = []
    }

    public typealias Judge = @Sendable (Claim, [FetchedPage]) -> (verdict: ClaimVerdict, page: Int, quote: String)

    /// The cases the dev set gives, and a line for each claim or variant that could not be built. `pageText` finds the
    /// truth source's text; a claim with none is skipped.
    public static func cases(from claims: [DevClaim], pageText: (DevClaim) -> String?) -> (
        cases: [Case], skipped: [String]
    ) {
        var cases: [Case] = []
        var skipped: [String] = []
        for dev in claims {
            guard let text = pageText(dev), let url = URL(string: dev.truthSourceUrl) else {
                skipped.append("\(dev.id): no truth source text in the fixture")
                continue
            }
            let page = FetchedPage(url: url, text: text)
            func claim(_ words: String, value: String) -> Claim {
                Claim(deal: dev.company, text: words, type: dev.type, value: value, quote: words, line: 0)
            }
            cases.append(
                Case(
                    id: dev.id + " planted", claim: claim(dev.claimText, value: dev.plantedWrongValue), page: page,
                    expected: .contradicted))
            guard dev.claimText.contains(dev.plantedWrongValue) else {
                skipped.append("\(dev.id): true variant skipped, the wrong value is not written in the claim text")
                continue
            }
            let right = dev.claimText.replacingOccurrences(of: dev.plantedWrongValue, with: dev.trueValue)
            cases.append(
                Case(id: dev.id + " true", claim: claim(right, value: dev.trueValue), page: page, expected: .supported))
        }
        return (cases, skipped)
    }

    public static func run(_ cases: [Case], judge: Judge) -> Report {
        var report = Report()
        for item in cases {
            let raw = judge(item.claim, [item.page])
            let verdict = ClaimChecker.settle(
                RawVerdict(verdict: raw.verdict, page: raw.page, quote: raw.quote), pages: [item.page]
            ).verdict
            switch item.expected {
            case .contradicted:
                report.planted += 1
                if verdict == .contradicted { report.plantedContradicted += 1 }
                if verdict == .supported { report.plantedSupported += 1 }
            default:
                report.trueClaims += 1
                if verdict == .supported { report.trueSupported += 1 }
                if verdict == .contradicted { report.trueContradicted += 1 }
            }
        }
        return report
    }
}
