import Foundation

/// The read-only server of the page-eval tools: JSON-RPC over lines. It answers `initialize`, `tools/list` and
/// `tools/call`, gives an empty result to any other request and ignores notifications. A call above the cap is
/// refused with a tool error. No tool writes anything.
public struct PageToolService {
    public static let toolNames = ["facts", "count", "page"]
    public static let defaultLimit = 40

    public let fixture: PageToolFixture
    public let callCap: Int
    private var calls = 0

    public init(fixture: PageToolFixture, callCap: Int) {
        self.fixture = fixture
        self.callCap = callCap
    }

    /// The reply line for one request line (nil for a notification or a line that is not JSON), and the log entry of
    /// a tool call.
    public mutating func respond(to line: String) -> (reply: String?, log: PageToolLogEntry?) {
        guard let request = Self.object(of: line), let id = request["id"] else { return (nil, nil) }
        let method = request["method"] as? String ?? ""
        let params = request["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return (
                Self.reply(
                    id,
                    [
                        "protocolVersion": params["protocolVersion"] ?? "2025-06-18", "capabilities": ["tools": [:]],
                        "serverInfo": ["name": "page", "version": "0"],
                    ]), nil
            )
        case "tools/list": return (Self.reply(id, ["tools": Self.tools]), nil)
        case "tools/call":
            let (result, entry) = call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:])
            return (Self.reply(id, result), entry)
        default: return (Self.reply(id, [:]), nil)
        }
    }

    private mutating func call(_ tool: String, _ arguments: [String: Any]) -> ([String: Any], PageToolLogEntry) {
        calls += 1
        let described = Self.text(of: arguments)
        guard calls <= callCap else {
            let words = "Call limit of \(callCap) reached. Make no more tool calls. Answer with what you have."
            return Self.toolResult(
                words, isError: true,
                log: PageToolLogEntry(
                    tool: tool, arguments: described, resultBytes: words.utf8.count, isError: true, refused: true,
                    returnedHandles: []))
        }
        switch answer(tool, arguments) {
        case .success(let (answer, handles)):
            let words = Self.text(of: answer)
            return Self.toolResult(
                words, isError: false,
                log: PageToolLogEntry(
                    tool: tool, arguments: described, resultBytes: words.utf8.count, isError: false, refused: false,
                    returnedHandles: handles))
        case .failure(let message):
            return Self.toolResult(
                message.words, isError: true,
                log: PageToolLogEntry(
                    tool: tool, arguments: described, resultBytes: message.words.utf8.count, isError: true,
                    refused: false, returnedHandles: []))
        }
    }

    private struct Failure: Error { let words: String }

    private func answer(_ tool: String, _ arguments: [String: Any]) -> Result<([String: Any], [String]), Failure> {
        switch tool {
        case "page":
            return .success((page, fixture.blocks.compactMap { $0.split(separator: " ").first.map(String.init) }))
        case "facts", "count":
            let filters = (arguments["filter"] as? [[String: Any]] ?? []).map {
                PageToolQuery.Filter(field: $0["field"] as? String ?? "", values: $0["values"] as? [String] ?? [])
            }
            let groupBy = (arguments["groupBy"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let fields = arguments["fields"] as? [String] ?? []
            let query = PageToolQuery(fixture: fixture, filters: filters, groupBy: groupBy)
            let grouped = filters.map(\.field) + [groupBy].compactMap { $0 }
            if let message = PageToolQuery.unknownFieldMessage(in: grouped, known: query.knownFields)
                ?? PageToolQuery.unknownFieldMessage(in: fields, known: query.shownFields)
            {
                return .failure(Failure(words: message))
            }
            if tool == "count" { return .success((query.count(), [])) }
            let limit = (arguments["limit"] as? Int).map { max($0, 1) } ?? Self.defaultLimit
            return .success(query.facts(fields: fields, limit: limit))
        default:
            return .failure(
                Failure(words: "Unknown tool \"\(tool)\". Tools: \(Self.toolNames.joined(separator: ", "))."))
        }
    }

    private var page: [String: Any] {
        [
            "blocks": fixture.blocks, "machineBlocks": fixture.machineBlockCount, "blockCap": fixture.blockCap,
            "catalog": Dictionary(uniqueKeysWithValues: fixture.catalog.map { ($0.field, $0.values) }),
            "columns": fixture.columns,
        ]
    }

    // MARK: JSON-RPC

    private static func toolResult(
        _ words: String, isError: Bool, log: PageToolLogEntry
    ) -> ([String: Any], PageToolLogEntry) {
        (["content": [["type": "text", "text": words]], "isError": isError], log)
    }

    private static func reply(_ id: Any, _ result: [String: Any]) -> String {
        text(of: ["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func object(of line: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private static func text(of value: Any) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private static var filterSchema: [String: Any] {
        [
            "type": "array", "description": "Each item names a field and the values to keep. No filter keeps all.",
            "items": [
                "type": "object",
                "properties": ["field": ["type": "string"], "values": ["type": "array", "items": ["type": "string"]]],
                "required": ["field", "values"],
            ],
        ]
    }

    private static var tools: [[String: Any]] {
        [
            [
                "name": "facts",
                "description":
                    "Lists facts as a handle (F1, …) and the asked fields. Says how many matched in all. Reads only.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "filter": filterSchema,
                        "groupBy": ["type": "string", "description": "A field to group the facts by."],
                        "fields": [
                            "type": "array", "items": ["type": "string"],
                            "description": "Fields to show; quote is the exact words.",
                        ],
                        "limit": [
                            "type": "integer", "description": "At most this many facts; default \(defaultLimit).",
                        ],
                    ],
                ],
            ],
            [
                "name": "count",
                "description":
                    "Counts the matching facts, in all or by the value of a field. Code computes the numbers.",
                "inputSchema": [
                    "type": "object", "properties": ["filter": filterSchema, "groupBy": ["type": "string"]],
                ],
            ],
            [
                "name": "page",
                "description":
                    "The blocks of the page in order (B1, …), the cap of machine blocks, the catalog of fields and values a filter or grouping may use, and the columns a table may show.",
                "inputSchema": ["type": "object", "properties": [String: Any]()],
            ],
        ]
    }
}
