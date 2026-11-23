import CryptoKit
import Foundation

/// A JSON schema in the small subset the models are held to. Every object property is required.
public indirect enum JSONSchema: Sendable, Equatable {
    public struct Property: Sendable, Equatable {
        public var name: String
        public var schema: JSONSchema

        public init(_ name: String, _ schema: JSONSchema) {
            self.name = name
            self.schema = schema
        }
    }

    case object([Property])
    case array(JSONSchema)
    case string
    case boolean
    case integer
    case number
    case enumeration([String])

    /// The schema of a string-valued enum: one of its raw values.
    public static func choice<E: CaseIterable & RawRepresentable>(_ type: E.Type) -> JSONSchema
    where E.RawValue == String {
        .enumeration(type.allCases.map(\.rawValue))
    }

    /// Whether JSON text fits this schema as the CLIs enforce it: every property present, no other, each of the
    /// right type. Code checks every reply with it, whatever the model promised (OWASP LLM01: validate output).
    public func accepts(json text: String) -> Bool {
        guard let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return false }
        return accepts(value)
    }

    func accepts(_ value: Any) -> Bool {
        let isBool = { (number: NSNumber) in CFGetTypeID(number) == CFBooleanGetTypeID() }
        switch self {
        case .object(let properties):
            guard let object = value as? [String: Any], Set(object.keys) == Set(properties.map(\.name)) else {
                return false
            }
            return properties.allSatisfy { property in object[property.name].map(property.schema.accepts) ?? false }
        case .array(let element): return (value as? [Any])?.allSatisfy(element.accepts) ?? false
        case .string: return value is String
        case .boolean: return (value as? NSNumber).map(isBool) ?? false
        case .integer:
            guard let number = value as? NSNumber, !isBool(number) else { return false }
            return number.doubleValue == number.doubleValue.rounded()
        case .number: return (value as? NSNumber).map { !isBool($0) } ?? false
        case .enumeration(let values): return (value as? String).map(values.contains) ?? false
        }
    }

    /// The schema as JSON text in the strict form the CLI accepts: every property required, no extras.
    public var jsonText: String {
        get throws {
            let data = try JSONSerialization.data(
                withJSONObject: jsonObject, options: [.sortedKeys, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        }
    }

    private var jsonObject: [String: Any] {
        switch self {
        case .object(let properties):
            [
                "type": "object",
                "properties": Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0.schema.jsonObject) }),
                "required": properties.map(\.name),
                "additionalProperties": false,
            ]
        case .array(let element): ["type": "array", "items": element.jsonObject]
        case .string: ["type": "string"]
        case .boolean: ["type": "boolean"]
        case .integer: ["type": "integer"]
        case .number: ["type": "number"]
        case .enumeration(let values): ["type": "string", "enum": values]
        }
    }
}

/// What one model call cost, as the model reported it.
public struct Usage: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    public var outputTokens: Int
    /// At list price. On a subscription this is what the call would have cost, not what was billed.
    public var costUSD: Double

    public init(
        inputTokens: Int = 0, cacheReadTokens: Int = 0, cacheWriteTokens: Int = 0, outputTokens: Int = 0,
        costUSD: Double = 0
    ) {
        self.inputTokens = inputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
    }

    public var tokens: Int { inputTokens + cacheReadTokens + cacheWriteTokens + outputTokens }

    public static func + (lhs: Usage, rhs: Usage) -> Usage {
        Usage(
            inputTokens: lhs.inputTokens + rhs.inputTokens, cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            cacheWriteTokens: lhs.cacheWriteTokens + rhs.cacheWriteTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens, costUSD: lhs.costUSD + rhs.costUSD)
    }
}

public struct ModelAnswer<Value: Sendable>: Sendable {
    public var value: Value
    /// The model that answered, as it named itself.
    public var model: String
    public var usage: Usage
    /// The reply as the model gave it: JSON text.
    public var reply: String

    public init(value: Value, model: String, usage: Usage, reply: String) {
        self.value = value
        self.model = model
        self.usage = usage
        self.reply = reply
    }
}

/// The seam to any model that can return a value of a schema. An adapter throws on a reply that does not decode; it
/// never repairs one.
public protocol StructuredModel: Sendable {
    /// The model asked for, such as "opus".
    var name: String { get }
    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
}

public enum StructuredModelError: Error, Equatable {
    /// The reply did not decode into the schema.
    case invalidReply(String)
    case unavailable(String)
}

extension StructuredModelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidReply: "The model gave an answer Workbench could not read."
        case .unavailable(let reason): "The model is not available: \(reason)"
        }
    }
}

/// Any JSON value, for a reply whose shape is data rather than a Swift type.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    /// A whole number, as models write ids.
    public var integer: Int64? {
        if case .number(let value) = self, value == value.rounded(), abs(value) < 1e15 { Int64(value) } else { nil }
    }
}

enum Digest {
    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
