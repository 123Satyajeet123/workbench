import Foundation
import WorkbenchCore

/// What the JSON event stream of one `codex exec --json` run says about usage and failure.
struct CodexEvents: Sendable, Equatable {
    private(set) var usage = Usage()
    private(set) var completed = false
    private(set) var failure: String?

    private struct Event: Decodable {
        struct Counts: Decodable {
            var inputTokens = 0
            var cachedInputTokens = 0
            var outputTokens = 0

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
                cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
                outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
            }

            private enum CodingKeys: String, CodingKey { case inputTokens, cachedInputTokens, outputTokens }
        }

        struct Failure: Decodable { var message: String? }

        var type: String
        var usage: Counts?
        var error: Failure?
        var message: String?
    }

    /// Cached input is part of the input count, so it is moved out of it. Codex reports no cost.
    init(stdout: String) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var lastError: String?
        for line in stdout.split(separator: "\n") {
            guard let event = try? decoder.decode(Event.self, from: Data(line.utf8)) else { continue }
            switch event.type {
            case "turn.completed":
                completed = true
                if let counts = event.usage {
                    usage =
                        usage
                        + Usage(
                            inputTokens: counts.inputTokens - counts.cachedInputTokens,
                            cacheReadTokens: counts.cachedInputTokens, outputTokens: counts.outputTokens)
                }
            case "turn.failed": failure = event.error?.message ?? "turn failed"
            case "error": lastError = event.message
            default: break
            }
        }
        if !completed, failure == nil { failure = lastError }
    }
}
