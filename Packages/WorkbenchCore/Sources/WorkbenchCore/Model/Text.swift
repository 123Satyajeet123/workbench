import Foundation

extension String {
    public var nfc: String { precomposedStringWithCanonicalMapping }

    public var comparable: String {
        nfc.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public var cleaned: String? {
        let text = trimmingCharacters(in: .whitespacesAndNewlines).nfc
        return text.isEmpty ? nil : text
    }

    public func contains(quote: String) -> Bool {
        let quote = quote.comparable
        return !quote.isEmpty && comparable.contains(quote)
    }
}
