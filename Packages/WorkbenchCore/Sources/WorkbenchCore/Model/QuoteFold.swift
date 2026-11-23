import Foundation

/// A text in the form a quote is looked up in. It is in Unicode normal form C and lower case. Each run of white
/// space is one space. Curly and straight quotation marks are one mark each, a danda is a full stop, and zero-width
/// characters are gone. Each folded character keeps the place of the character it came from, so a match in the folded
/// text gives the place of the quote in the text.
struct FoldedText {
    private(set) var scalars: [Unicode.Scalar] = []
    /// For each folded character, the offset of its source in the normal form C text, counted in Unicode scalars.
    private(set) var origins: [Int] = []

    private static let zeroWidth: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]

    private static let marks: [Unicode.Scalar: Unicode.Scalar] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'", "\u{02BC}": "'", "\u{2032}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"", "\u{00AB}": "\"", "\u{00BB}": "\"",
        "\u{0964}": ".", "\u{0965}": ".",
    ]

    init(_ text: String) {
        var spaceAt: Int?
        for (offset, scalar) in text.nfc.unicodeScalars.enumerated() {
            if scalar.properties.isWhitespace {
                if !scalars.isEmpty { spaceAt = spaceAt ?? offset }
            } else if !Self.zeroWidth.contains(scalar) {
                if let at = spaceAt {
                    append(" ", from: at)
                    spaceAt = nil
                }
                for folded in scalar.properties.lowercaseMapping.unicodeScalars {
                    append(Self.marks[folded] ?? folded, from: offset)
                }
            }
        }
    }

    private mutating func append(_ scalar: Unicode.Scalar, from origin: Int) {
        scalars.append(scalar)
        origins.append(origin)
    }

    var text: String { String(String.UnicodeScalarView(scalars)) }

    /// Where `quote` first occurs, in folded characters. Exact: every character of the quote must be there, in order.
    /// An empty quote occurs nowhere.
    func range(of quote: FoldedText) -> Range<Int>? {
        quote.scalars.isEmpty ? nil : scalars.firstRange(of: quote.scalars)
    }

    /// The offsets in the normal form C text of the characters a folded range covers.
    func source(of range: Range<Int>) -> Range<Int> {
        origins[range.lowerBound]..<(origins[range.upperBound - 1] + 1)
    }
}

extension String {
    /// Where `quote` is in this text, as offsets in Unicode scalars of this text in normal form C. It is found when
    /// the two are the same after the fold of `FoldedText`, and in no other case.
    public func span(of quote: String) -> Range<Int>? {
        let text = FoldedText(self)
        return text.range(of: FoldedText(quote)).map(text.source(of:))
    }
}
