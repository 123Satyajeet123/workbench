import Foundation

public enum LexicalJudge {
    nonisolated(unsafe) private static let amountPattern =
        #/(?i)(\d+(?:\.\d+)?)\s?(million|mn|crore|cr|billion|bn|lakh)\b/#
    nonisolated(unsafe) private static let yearPattern = #/\b(19|20)\d{2}\b/#
    private static let scale = [
        "million": 1e6, "mn": 1e6, "crore": 1e7, "cr": 1e7, "billion": 1e9, "bn": 1e9, "lakh": 1e5,
    ]

    public static func judge(_ claim: Claim, pages: [FetchedPage]) -> (verdict: ClaimVerdict, page: Int, quote: String)
    {
        for (index, page) in pages.enumerated() {
            if let found = verdict(for: claim, in: page.text) { return (found.verdict, index + 1, found.quote) }
        }
        return (.unclear, 0, "")
    }

    private static func verdict(for claim: Claim, in text: String) -> (verdict: ClaimVerdict, quote: String)? {
        if let wanted = amount(of: claim.value) {
            let amounts = text.matches(of: amountPattern).map { (number(of: $0.output), String($0.output.0)) }
            if let same = amounts.first(where: { $0.0 == wanted }) { return (.supported, same.1) }
            return amounts.first.map { (.contradicted, $0.1) }
        }
        if let wanted = claim.value.firstMatch(of: yearPattern).map({ String($0.output.0) }) {
            let years = text.matches(of: yearPattern).map { String($0.output.0) }
            if years.contains(wanted) { return (.supported, wanted) }
            return years.first.map { (.contradicted, $0) }
        }
        guard let range = text.range(of: claim.value, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        return (.supported, String(text[range]))
    }

    private static func amount(of text: String) -> Double? {
        text.firstMatch(of: amountPattern).map { number(of: $0.output) }
    }

    private static func number(of match: (Substring, Substring, Substring)) -> Double {
        (Double(match.1) ?? 0) * (scale[match.2.lowercased()] ?? 1)
    }
}
