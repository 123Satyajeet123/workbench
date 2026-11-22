// Source: built (RFC 8785 §3.1 and RFC 7493 I-JSON, restricted to integers and strings: research K7 §3.1).

/// The closed set of JSON values that may be signed: no floats, integers only inside the I-JSON range. Strings are
/// kept exactly as given; two strings are equal only when their Unicode scalars are equal, never by canonical
/// equivalence.
public indirect enum JSONValue: Sendable {
    public static let maximumInteger: Int64 = (1 << 53) - 1
    public static let integerRange = -maximumInteger...maximumInteger
    public static let maximumDepth = 64

    case null
    case bool(Bool)
    case integer(Int64)
    case string(String)
    case array([JSONValue])
    case object([JSONMember])
}

/// One key and value of an object, in the order given. The encoder sorts members and refuses duplicate keys.
public struct JSONMember: Sendable, Equatable {
    public let key: String
    public let value: JSONValue

    public init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }

    public static func == (lhs: JSONMember, rhs: JSONMember) -> Bool {
        lhs.key.unicodeScalars.elementsEqual(rhs.key.unicodeScalars) && lhs.value == rhs.value
    }
}

public enum JSONError: Error, Equatable, Sendable {
    case floatNotAllowed
    case integerOutOfRange
    case duplicateKey(String)
    case loneSurrogate
    case controlCharacter
    case invalidUTF8
    case tooDeep
    case invalidSyntax(at: Int)
    case trailingContent(at: Int)
}

extension JSONValue: Equatable {
    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case (.bool(let left), .bool(let right)): left == right
        case (.integer(let left), .integer(let right)): left == right
        case (.string(let left), .string(let right)): left.unicodeScalars.elementsEqual(right.unicodeScalars)
        case (.array(let left), .array(let right)): left == right
        case (.object(let left), .object(let right)): canonicalOrder(left) == canonicalOrder(right)
        default: false
        }
    }

    /// Members in RFC 8785 key order, so member order never decides equality.
    static func canonicalOrder(_ members: [JSONMember]) -> [JSONMember] {
        members.sorted { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }
    }
}
