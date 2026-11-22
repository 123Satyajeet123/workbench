import Foundation
import WorkbenchCore

/// A model that answers a page from the candidates saved for its address, so an eval runs with no model and no
/// network. The reply is built to fit the schema it is asked for: a field the saved candidate lacks is empty, a rule
/// with no saved answer is "unclear", and the citation is the page's line.
public struct ReplayModel: StructuredModel {
    public let name = "replay"
    private let candidates: [String: [[String: String]]]

    public init(_ saved: [OutboundFixture.Saved]) {
        candidates = Dictionary(saved.map { ($0.url, $0.candidates) }, uniquingKeysWith: { first, _ in first })
    }

    public func generate<T: Decodable & Sendable>(
        _ type: T.Type, schema: JSONSchema, instructions: String, input: String
    ) async throws -> ModelAnswer<T> {
        let own = candidates.first { input.contains($0.key) }?.value ?? []
        let items = own.map { saved in Self.fill(schema.itemSchema, with: saved) }
        let reply = String(
            decoding: try JSONSerialization.data(withJSONObject: ["items": items], options: [.sortedKeys]),
            as: UTF8.self)
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: name, usage: Usage(), reply: reply)
    }

    private static func fill(_ properties: [JSONSchema.Property], with saved: [String: String]) -> [String: Any] {
        Dictionary(
            uniqueKeysWithValues: properties.map { property in
                let value: Any =
                    switch property.schema {
                    case .integer: Outbound.pageLine
                    case .enumeration(let values):
                        saved[property.name] ?? (values.contains("unclear") ? "unclear" : values[0])
                    default: saved[property.name] ?? ""
                    }
                return (property.name, value)
            })
    }
}

extension JSONSchema {
    /// The properties of one item of the reply's `items` array; empty for any other schema.
    fileprivate var itemSchema: [Property] {
        guard case .object(let properties) = self, let items = properties.first(where: { $0.name == "items" }),
            case .array(.object(let item)) = items.schema
        else { return [] }
        return item
    }
}
