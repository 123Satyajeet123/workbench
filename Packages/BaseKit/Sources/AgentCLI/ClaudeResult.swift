import Foundation
import WorkbenchCore

public struct ClaudeResult: Sendable, Equatable {
    public let isError: Bool
    public let text: String?
    public let structuredAnswer: String?
    /// Summed over every model the run used; the cost is the run's total at list price.
    public let usage: Usage
    /// The model that cost the most in the run, as claude names it.
    public let model: String?

    public init?(line: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            object["type"] as? String == "result"
        else { return nil }
        isError = object["is_error"] as? Bool != false || (object["subtype"] as? String ?? "success") != "success"
        text = object["result"] as? String
        structuredAnswer = object["structured_output"].flatMap(Self.json(of:))
        let models = object["modelUsage"] as? [String: [String: Any]] ?? [:]
        model = models.max { Self.number($0.value["costUSD"]) < Self.number($1.value["costUSD"]) }?.key
        func total(_ key: String) -> Int { models.values.reduce(0) { $0 + Int(Self.number($1[key])) } }
        usage = Usage(
            inputTokens: total("inputTokens"), cacheReadTokens: total("cacheReadInputTokens"),
            cacheWriteTokens: total("cacheCreationInputTokens"), outputTokens: total("outputTokens"),
            costUSD: Self.number(object["total_cost_usd"]))
    }

    public static func last(in stdout: String) -> ClaudeResult? {
        stdout.split(separator: "\n").reversed().lazy.compactMap { ClaudeResult(line: String($0)) }.first
    }

    private static func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }

    private static func json(of value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
