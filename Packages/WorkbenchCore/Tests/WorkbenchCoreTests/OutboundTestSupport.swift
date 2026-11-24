import Foundation
import Synchronization

@testable import WorkbenchCore

/// Answers the query call with a fixed reply and each page call with the reply whose address the input holds. It
/// remembers every input, so a test can see which calls ran.
final class OutboundModel: StructuredModel, Sendable {
    let name = "outbound"
    let queries: String
    let pages: [String: String]
    let inputs = Mutex<[String]>([])

    init(queries: String = OutboundModel.defaultQueries, pages: [String: String] = [:]) {
        self.queries = queries
        self.pages = pages
    }

    static let defaultQueries =
        #"{"criteria":[{"rule":"r_stage","queries":["seed funding india startups","pre-seed round announced"]},{"rule":"r_traction","queries":["startup crosses 100 customers"]}]}"#

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        inputs.withLock { $0.append(input) }
        let reply =
            instructions == OutboundQueries.instructions(for: WorkspaceProfile())
            ? queries : pages.first { input.contains($0.key) }?.value ?? #"{"items":[]}"#
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: "m", usage: Usage(costUSD: 0.01),
            reply: reply)
    }

    /// The calls that read a page: their input starts with the work day.
    var pageCalls: Int { inputs.withLock { $0 }.filter { $0.hasPrefix("Work day") }.count }
}

/// One candidate in a page reply, with an answer and a quote for the two starter rules.
func candidateJSON(
    _ company: String, domain: String = "", stage: String = "yes", stageQuote: String, traction: String = "unclear",
    tractionQuote: String = "", quote: String
) -> String {
    #"""
    {"company":"\#(company)","domain":"\#(domain)","sector":"fintech","r_stage":"\#(stage)","r_stage_quote":"\#(stageQuote)","r_stage_reason":"r","r_traction":"\#(traction)","r_traction_quote":"\#(tractionQuote)","r_traction_reason":"r","cite":1,"quote":"\#(quote)"}
    """#
}

func pageReply(_ candidates: String...) -> String { #"{"items":[\#(candidates.joined(separator: ","))]}"# }

extension Store {
    /// A deal in `stage`, written as the Deals page writes it.
    @discardableResult
    func addDeal(_ title: String, stage: String = "Inbox") throws -> String {
        let id = UUID().uuidString
        let first = try queries.nextClock()
        try append([
            WorkEvent(object: id, author: "Asha", clock: first, at: t0, kind: .create, text: "deal"),
            WorkEvent(object: id, author: "Asha", clock: first + 1, at: t0, kind: .title, text: title),
            WorkEvent(object: id, author: "Asha", clock: first + 2, at: t0, kind: .stage, text: stage),
        ])
        return id
    }

    /// The candidates the outbound machine of `task` holds, as stored.
    func candidates(task: String = Outbound.task) throws -> [Item] {
        try queries.items(of: task, since: WorkDay(containing: t0).adding(days: -1))
    }
}

func hit(_ address: String) -> SearchHit { SearchHit(title: "", url: URL(string: address)!, snippet: "") }
