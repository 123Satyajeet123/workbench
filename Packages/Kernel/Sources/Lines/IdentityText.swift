// Source: built (research 56 §1, research E-R1 §4.2 defect 4; ADR-014). The white space set is the Unicode
// White_Space property (PropList.txt); a test checks it against the platform's property for every scalar.

import Foundation

/// The form of a text that its identity is hashed from. Two readings of one line that differ only in canonical
/// spelling (NFC or NFD), in runs of white space, in white space at the ends, or in invisible format and direction
/// marks, give one identity text. Case, letters, marks, ZWJ and ZWNJ are kept.
public enum IdentityText {
    /// Removes the invisible characters, folds each run of white space into one space and trims the ends, then
    /// normalizes to NFC last: a mark that followed a removed character combines with its letter.
    public static func normalize(_ text: String) -> String {
        var utf8: [UInt8] = []
        utf8.reserveCapacity(text.utf8.count)
        var spacePending = false
        for scalar in text.unicodeScalars where !isInvisible(scalar.value) {
            if isWhiteSpace(scalar.value) {
                spacePending = !utf8.isEmpty
                continue
            }
            if spacePending {
                utf8.append(0x20)
                spacePending = false
            }
            utf8.append(contentsOf: UTF8.encode(scalar)!)
        }
        return String(decoding: utf8, as: UTF8.self).precomposedStringWithCanonicalMapping
    }

    /// Soft hyphen, zero width space, word joiner, zero width no-break space (the byte order mark), and the
    /// direction marks: Arabic letter mark, left-to-right and right-to-left marks, embeddings, overrides and isolates.
    static func isInvisible(_ value: UInt32) -> Bool {
        switch value {
        case 0xAD, 0x61C, 0x200B, 0x200E, 0x200F, 0x202A...0x202E, 0x2060, 0x2066...0x2069, 0xFEFF: true
        default: false
        }
    }

    /// The Unicode White_Space property, as a table.
    static func isWhiteSpace(_ value: UInt32) -> Bool {
        switch value {
        case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: true
        default: false
        }
    }
}
