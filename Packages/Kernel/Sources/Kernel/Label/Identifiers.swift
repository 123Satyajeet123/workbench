// Source: built (review 1 F1: one equality for every name).

import Foundation

/// A name made of text. The text is normalized to NFC when the name is made, and names are equal, hashed and sorted
/// by the UTF-8 bytes of that text, so two spellings of one name are one name everywhere.
public protocol StringIdentifier: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The NFC text of the name.
    var rawValue: String { get }
    /// Refuses empty text and text with a control character.
    init(_ text: String) throws(IdentifierError)
}

public enum IdentifierError: Error, Equatable, Sendable {
    case empty
    case controlCharacter
}

extension StringIdentifier {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }
    public var description: String { rawValue }
    var utf8Bytes: [UInt8] { Array(rawValue.utf8) }
}

/// NFC text compared and hashed by its UTF-8 bytes. Identifier types store one, so their synthesized `==` and `hash`
/// use the bytes.
struct NFCText: Hashable, Sendable {
    let value: String

    init(_ text: String) throws(IdentifierError) {
        let normalized = text.precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty else { throw .empty }
        guard !normalized.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw .controlCharacter
        }
        value = normalized
    }

    static func == (lhs: NFCText, rhs: NFCText) -> Bool { lhs.value.utf8.elementsEqual(rhs.value.utf8) }

    func hash(into hasher: inout Hasher) {
        for byte in value.utf8 { hasher.combine(byte) }
    }
}

/// A person on the team. Labels and grants name people; keys name their devices.
public struct PersonID: StringIdentifier {
    private let text: NFCText
    public var rawValue: String { text.value }
    public init(_ text: String) throws(IdentifierError) { self.text = try NFCText(text) }
}

/// An owner's own name for one of their sources, such as `wa:founders`. Unique per owner, not across owners.
public struct SourceKey: StringIdentifier {
    private let text: NFCText
    public var rawValue: String { text.value }
    public init(_ text: String) throws(IdentifierError) { self.text = try NFCText(text) }
}

/// A kind of content that release rules read, such as `personal` or `money`. Classes never decide readers.
public struct SourceClass: StringIdentifier {
    private let text: NFCText
    public var rawValue: String { text.value }
    public init(_ text: String) throws(IdentifierError) { self.text = try NFCText(text) }
}
