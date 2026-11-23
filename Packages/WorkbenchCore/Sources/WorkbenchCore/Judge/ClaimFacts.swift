import Foundation
import NaturalLanguage

/// The facts of a claim that code can check against a cited text without reading its meaning: the amounts and years it
/// states (a number with its scale, so "$11 million" and "$11 Mn" are one amount), the months it names, and the proper
/// names in it. Words come from the platform tokenizer, so Devanagari and Roman Hinglish tokenize as English does.
struct ClaimFacts: Equatable {
    var amounts: Set<Decimal> = []
    var months: Set<Int> = []
    var names: Set<String> = []

    /// The facts of `text`. The words of `subject`, the one the claim is about, are not facts to check.
    init(of text: String, ignoring subject: String = "") {
        let words = Words(of: text)
        let given = Set(Words(of: subject).tokens.map(\.folded))
        var index = 0
        while index < words.tokens.count {
            let token = words.tokens[index]
            index += 1
            if let amount = Amount(token.text) {
                var scale = amount.scale
                if scale == nil, let next = words.tokens[safe: index].flatMap({ Amount.scale(word: $0.folded) }) {
                    scale = next
                    index += 1
                }
                amounts.insert(amount.value * (scale ?? 1))
            } else if token.isCapitalised, let month = Self.month(token.folded) {
                months.insert(month)
            } else if token.isName, !given.contains(token.folded) {
                names.insert(token.folded)
            }
        }
    }

    var isEmpty: Bool { amounts.isEmpty && months.isEmpty && names.isEmpty }

    /// The facts of this claim that `cited` does not hold, each as the words a person reads.
    func missing(from cited: CitedVocabulary) -> [String] {
        amounts.subtracting(cited.amounts).sorted().map { $0.formatted(.number.locale(Locale(identifier: "en_US"))) }
            + months.subtracting(cited.months).sorted().map { Calendar(identifier: .gregorian).monthSymbols[$0 - 1] }
            + names.subtracting(cited.words).sorted()
    }

    private static func month(_ word: String) -> Int? {
        let calendar = Calendar(identifier: .gregorian)
        let index =
            calendar.monthSymbols.firstIndex { $0.lowercased() == word }
            ?? calendar.shortMonthSymbols.firstIndex { $0.lowercased() == word || $0.lowercased() + "t" == word }
        return index.map { $0 + 1 }
    }
}

/// What a cited text holds, in the same terms as `ClaimFacts`: every word, every amount and every month.
struct CitedVocabulary: Equatable {
    var words: Set<String> = []
    var amounts: Set<Decimal> = []
    var months: Set<Int> = []

    init(of text: String) {
        let tokens = Words(of: text).tokens
        words = Set(tokens.map(\.folded))
        for (index, token) in tokens.enumerated() {
            guard let amount = Amount(token.text) else { continue }
            let scale = amount.scale ?? tokens[safe: index + 1].flatMap { Amount.scale(word: $0.folded) }
            amounts.insert(amount.value * (scale ?? 1))
            amounts.insert(amount.value)
        }
        let calendar = Calendar(identifier: .gregorian)
        for (index, name) in calendar.monthSymbols.enumerated() {
            let short = calendar.shortMonthSymbols[index].lowercased()
            if words.contains(name.lowercased()) || words.contains(short) || words.contains(short + "t") {
                months.insert(index + 1)
            }
        }
    }
}

/// A number written in a text, with the scale its own letters give: "11M", "10cr", "1,200".
struct Amount {
    var value: Decimal
    var scale: Decimal?

    private static let scales: [String: Decimal] = [
        "thousand": 1_000, "k": 1_000, "million": 1_000_000, "mn": 1_000_000, "mm": 1_000_000, "m": 1_000_000,
        "billion": 1_000_000_000, "bn": 1_000_000_000, "b": 1_000_000_000, "lakh": 100_000, "lakhs": 100_000,
        "lac": 100_000, "crore": 10_000_000, "crores": 10_000_000, "cr": 10_000_000,
    ]

    /// The scale a separate word gives. Single letters count only when attached to the digits.
    static func scale(word: String) -> Decimal? { word.count > 1 ? scales[word] : nil }

    init?(_ written: String) {
        let token = written.drop { $0.unicodeScalars.allSatisfy { $0.properties.generalCategory == .currencySymbol } }
        let digits = token.prefix { $0.isNumber || $0 == "." || $0 == "," }
        guard !digits.isEmpty, digits.contains(where: \.isNumber) else { return nil }
        let rest = token.dropFirst(digits.count).lowercased()
        guard rest.isEmpty || Self.scales[rest] != nil else { return nil }
        let ascii = digits.filter { $0 != "," }.map { $0.wholeNumberValue.map(String.init) ?? String($0) }.joined()
        guard let value = Decimal(string: ascii) else { return nil }
        self.value = value
        scale = rest.isEmpty ? nil : Self.scales[rest]
    }
}

/// The word tokens of a text, each with the places a fact reader needs: its folded form, whether it starts with a capital
/// that is not just the start of a sentence, and whether the platform tagger takes it for a name.
struct Words {
    struct Token {
        var range: Range<String.Index>
        var text: String
        var folded: String
        var isCapitalised: Bool
        var startsSentence: Bool
        var isTaggedName: Bool

        var isName: Bool {
            guard Amount(text) == nil else { return false }
            return isTaggedName || (isCapitalised && !startsSentence && text.count > 2)
        }
    }

    let tokens: [Token]

    init(of text: String) {
        let whole = text.startIndex..<text.endIndex
        let sentences = NLTokenizer(unit: .sentence)
        sentences.string = text
        var sentenceStarts: Set<String.Index> = []
        sentences.enumerateTokens(in: whole) { range, _ in
            sentenceStarts.insert(range.lowerBound)
            return true
        }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var tagged: Set<String.Index> = []
        tagger.enumerateTags(in: whole, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation]) {
            tag, range in
            if let tag, Self.nameTags.contains(tag) { tagged.insert(range.lowerBound) }
            return true
        }
        let words = NLTokenizer(unit: .word)
        words.string = text
        var tokens: [Token] = []
        words.enumerateTokens(in: whole) { range, _ in
            let word = Self.withoutPossessive(String(text[range]))
            tokens.append(
                Token(
                    range: range, text: word, folded: FoldedText(word).text,
                    isCapitalised: word.first.map { $0.isUppercase && !word.allSatisfy { $0.isUppercase } } ?? false,
                    startsSentence: sentenceStarts.contains(range.lowerBound),
                    isTaggedName: tagged.contains(range.lowerBound)))
            return true
        }
        self.tokens = tokens
    }

    private static let nameTags: Set<NLTag> = [.personalName, .placeName, .organizationName]

    private static func withoutPossessive(_ word: String) -> String {
        for suffix in ["'s", "\u{2019}s"] where word.hasSuffix(suffix) { return String(word.dropLast(suffix.count)) }
        return word
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
