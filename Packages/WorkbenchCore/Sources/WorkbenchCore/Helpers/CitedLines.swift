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

    var line: String? {
        guard let id = item.id else { return nil }
        let values = fields.map { "\($0)=\(item[$0])" }.filter { !$0.hasSuffix("=") }
        let mark: String =
            switch item.state {
            case .confirmed: "right"
            case .rejected: "wrong"
            case .proposed: "unmarked"
            }
        let closed = item.closed.map { " — closed: \($0.outcome)" } ?? ""
        return "[\(id)] \(machine) · \(values.joined(separator: " ")) — \"\(item.quote)\" — \(mark)\(closed)"
    }
}

enum Cites {
    static func hold(_ cites: [Int64], within given: Set<Int64>) -> Bool {
        !cites.isEmpty && Set(cites).isSubset(of: given)
    }
}
