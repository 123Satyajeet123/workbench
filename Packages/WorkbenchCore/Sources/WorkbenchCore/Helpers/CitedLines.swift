import Foundation

public struct CitedSource: Sendable {
    public var machine: String
    public var fields: [String]
    public var item: Item

    public init(machine: String, fields: [String], item: Item) {
        self.machine = machine
        self.fields = fields
        self.item = item
    }

    /// The item as one input line: `[id] machine · field=value … — "quote" — mark`, and how it closed when it did.
    /// Nil for an item with no id, which nothing could cite.
    var line: String? {
        guard let id = item.id else { return nil }
        let values = fields.map { "\($0)=\(item[$0])" }.filter { !$0.hasSuffix("=") }
        let closed = item.closed.map { " — closed: \($0.outcome)" } ?? ""
        return "[\(id)] \(machine) · \(values.joined(separator: " ")) — \"\(item.quote)\" — \(item.state.word)\(closed)"
    }
}

/// The one guard on every line a model writes over items: it must cite, and only items it was given.
enum Cites {
    static func hold(_ cites: [Int64], within given: Set<Int64>) -> Bool {
        !cites.isEmpty && Set(cites).isSubset(of: given)
    }
}
