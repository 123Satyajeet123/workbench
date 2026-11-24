import Foundation

@testable import WorkbenchCore

/// One attempt: one request to one model, with everything the file keeps about it.
public struct PageEvalRecord: Codable, Sendable, Equatable {
    public struct Verdict: Codable, Sendable, Equatable {
        public var operation: String
        public var refusal: String?
        public var refusalWords: String?
    }

    public struct Block: Codable, Sendable, Equatable {
        public var place: String
        public var kind: String
        public var title: String?
        public var text: String?
        public var layout: String?
        public var groupBy: String?
        public var filters: [String: [String]]?
        public var columns: [String]?
        public var rows: [[String]]?
        public var cites: [String]?
    }

    public var model: String
    /// How the model got the facts: `one` call, or a loop over `tools`.
    public var arm: String
    public var task: String
    /// The kind of task, which the report counts together.
    public var group: String
    public var run: Int
    public var request: String
    public var page: String
    public var passed: Bool
    /// Why the call produced no proposal; nil when it did.
    public var callFailure: String?
    /// The reply of the model as it gave it, before the gate.
    public var reply: JSONValue?
    public var verdicts: [Verdict]
    public var note: String
    public var resultPage: [Block]
    public var windowLines: Int
    public var costUSD: Double
    public var inputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    public var outputTokens: Int
    /// Model turns of the call: 1 for one call; for the CLI the count it reports.
    public var turns: Int
    /// Calls of each tool, from the tool server's own log.
    public var toolCalls: [String: Int]
    /// Calls the server refused for being above its cap.
    public var refusedToolCalls: Int
    /// Calls the server answered with a tool error.
    public var toolErrors: Int
    /// Tool uses the CLI denied: any other tool than the three.
    public var permissionDenials: Int
    /// Distinct names in the reply that no tool returned.
    public var unfetchedNames: Int
    /// From the run row, which keeps whole seconds.
    public var runRowSeconds: Double
    public var wallSeconds: Double
}

extension PageEvalRecord {
    /// The names of the reasons a gate refuses, one per case of `PageRefusal`.
    static func reason(of refusal: PageRefusal) -> String {
        switch refusal {
        case .unknownBlock: "unknownBlock"
        case .personsBlock: "personsBlock"
        case .unknownPlace: "unknownPlace"
        case .tooManyBlocks: "tooManyBlocks"
        case .unknownField: "unknownField"
        case .unknownValue: "unknownValue"
        case .noCite: "noCite"
        case .unknownCite: "unknownCite"
        case .unevenGrid: "unevenGrid"
        case .formula: "formula"
        }
    }

    static func kind(of block: MachineBlock) -> String {
        switch block {
        case .heading: "heading"
        case .text: "text"
        case .facts: "facts"
        case .grid: "grid"
        case .picker: "picker"
        }
    }

    static func verdicts(of proposal: PageProposal) -> [Verdict] {
        proposal.verdicts.map { verdict in
            Verdict(
                operation: verdict.operation.map(describe) ?? "unformed", refusal: verdict.refusal.map(reason),
                refusalWords: verdict.refusal?.description)
        }
    }

    private static func describe(_ operation: PageOperation) -> String {
        switch operation {
        case .insert(let block, _): "insert \(kind(of: block))"
        case .update(_, let block): "update \(kind(of: block))"
        case .remove: "remove"
        }
    }

    /// The page as the file keeps it: each paragraph of the person and each machine block, in order. A cite is
    /// `fact N` (the id in `PageEvalFacts.json`), `paragraph N` (its place among the paragraphs) or `request`.
    static func blocks(of page: MachinePage, notes: [NoteBlock], fixtureIDs: [Int64: Int]) -> [Block] {
        let paragraphs = page.order.compactMap { if case .note(let id) = $0 { id } else { nil } }
        let words = Dictionary(notes.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        func cite(_ cite: PageCite) -> String {
            switch cite {
            case .fact(let id): "fact \(fixtureIDs[id].map(String.init) ?? "?")"
            case .note(let id): "paragraph \((paragraphs.firstIndex(of: id) ?? -1) + 1)"
            case .request: "request"
            }
        }
        return page.order.map { place in
            switch place {
            case .note(let id): Block(place: "person", kind: "paragraph", text: words[id])
            case .machine(let id): page.blocks[id].map { machine($0, cite) } ?? Block(place: "machine", kind: "missing")
            }
        }
    }

    private static func machine(_ block: MachineBlock, _ cite: (PageCite) -> String) -> Block {
        var summary = Block(place: "machine", kind: kind(of: block))
        switch block {
        case .heading(let text): summary.text = text
        case .text(let text):
            summary.text = text.text
            summary.cites = text.cites.map(cite)
        case .facts(let view):
            summary.title = view.title
            summary.layout = view.layout.rawValue
            summary.groupBy = view.groupBy
            summary.filters = view.filters
            summary.columns = view.columns
        case .grid(let grid):
            summary.title = grid.title
            summary.columns = grid.columns
            summary.rows = grid.rows
            summary.cites = grid.cites.map(cite)
        case .picker(let kind): summary.title = kind.rawValue
        }
        return summary
    }
}
