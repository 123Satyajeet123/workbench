import Foundation

extension String {
    /// The text in Unicode normal form C. Compare and search only text that went through this: one letter can
    /// have two spellings (a Devanagari letter with a nukta is one code point or a base letter plus a nukta).
    public var nfc: String { precomposedStringWithCanonicalMapping }

    /// `nfc`, lower-cased, with runs of white space made one space: the form two texts are compared in.
    public var comparable: String {
        nfc.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The text trimmed and in normal form C, or nil when nothing is left. Every text the founder types passes here.
    public var cleaned: String? {
        let text = trimmingCharacters(in: .whitespacesAndNewlines).nfc
        return text.isEmpty ? nil : text
    }

    /// Whether `quote` is in this text, ignoring spelling form, case and spacing.
    public func contains(quote: String) -> Bool {
        let quote = quote.comparable
        return !quote.isEmpty && comparable.contains(quote)
    }
}
