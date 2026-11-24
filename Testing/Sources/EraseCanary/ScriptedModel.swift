import Foundation
import Synchronization

@testable import WorkbenchCore

/// A model that answers each call with the next reply it was given. No network.
final class ScriptedModel: StructuredModel, Sendable {
    let name = "scripted"
    let planName: String? = nil
    let billedToPlanSignIn = false
    private let replies: [String]
    private let calls = Mutex(0)

    init(_ replies: [String]) { self.replies = replies }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        let call = calls.withLock { count -> Int in
            count += 1
            return count - 1
        }
        let reply = replies[min(call, replies.count - 1)]
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: name,
            usage: Usage(inputTokens: 100, outputTokens: 20, costUSD: 0.01), reply: reply)
    }
}

/// The reply of a reading of the team machine: items that each cite one line and quote words of it.
enum ScriptedReply {
    private static let noTime =
        #"{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""}"#

    static func item(text: String, cite: Int, quote: String) -> String {
        #"{"person":"Asha Example","project":"Login","kind":"done","text":"\#(text)","when":\#(noTime),"asks":"team","stance":"said","relation":{"kind":"new","handle":"","outcome":""},"cite":\#(cite),"quote":"\#(quote)"}"#
    }

    static func reply(_ items: [String]) -> String { #"{"items":[\#(items.joined(separator: ","))]}"# }
}
