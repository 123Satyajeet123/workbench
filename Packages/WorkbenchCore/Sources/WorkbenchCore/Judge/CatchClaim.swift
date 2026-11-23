import Foundation

/// The ways a catch item is made wrong. Each is a small error that a careless reader may pass.
public enum CatchKind: String, Codable, CaseIterable, Sendable {
    /// An amount in the claim is changed.
    case amount
    /// A year in the claim is moved.
    case year
    /// A name in the claim is replaced by another.
    case name
    /// A sentence with no cite at all.
    case unsupported

    /// What every catch is, by construction: wrong or unsupported.
    public static let truth = "wrong"
}

/// A known-bad claim, made by code from a real one (J3 §7): it is shown like any other claim and counted apart. It
/// never feeds the certificate or any training.
public enum CatchClaim {
    static let invented = ["Meridian", "Halcyon", "Northwind", "Corvid"]
    static let uncited = "The company is expected to list on a stock exchange within a year."

    /// The claim made wrong in this way, or nil when it has nothing of that kind to change.
    public static func make(from claim: ProductClaim, kind: CatchKind) -> ProductClaim? {
        switch kind {
        case .unsupported: return ProductClaim(text: uncited, cites: [])
        case .amount: return rewriting(claim) { token in changed(amount: token, wantsYear: false) }
        case .year: return rewriting(claim) { token in changed(amount: token, wantsYear: true) }
        case .name:
            return rewriting(claim) { token in
                token.isName ? invented.first { !claim.text.localizedCaseInsensitiveContains($0) } : nil
            }
        }
    }

    private static func rewriting(_ claim: ProductClaim, _ replacement: (Words.Token) -> String?) -> ProductClaim? {
        for token in Words(of: claim.text).tokens {
            guard let new = replacement(token) else { continue }
            var text = claim.text
            text.replaceSubrange(token.range, with: new)
            return ProductClaim(text: text, cites: claim.cites)
        }
        return nil
    }

    private static func changed(amount token: Words.Token, wantsYear: Bool) -> String? {
        guard let amount = Amount(token.text), amount.scale == nil else { return nil }
        let whole = NSDecimalNumber(decimal: amount.value).intValue
        let isYear = (1900...2100).contains(whole)
        guard isYear == wantsYear else { return nil }
        return String(isYear ? whole - 2 : whole + max(3, whole / 5))
    }
}
