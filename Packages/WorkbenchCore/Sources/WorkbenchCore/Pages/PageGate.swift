import Foundation

/// One change a machine asks for. It names only machine blocks: a machine has no way to say "change the person's
/// paragraph".
public enum PageOperation: Equatable, Sendable {
    /// A new block after `after`, or last when `after` is nil.
    case insert(MachineBlock, after: PageBlockRef?)
    case update(MachineBlockID, MachineBlock)
    case remove(MachineBlockID)
}

/// Why an operation was not applied. Each is said to the person in plain words.
public enum PageRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownBlock(String)
    case personsBlock
    case unknownPlace(String)
    case tooManyBlocks(Int)
    case unknownField(String)
    case unknownValue(field: String, value: String)
    case noCite
    case unknownCite(String)
    case unevenGrid
    case formula(String)

    public var description: String {
        switch self {
        case .unknownBlock(let name): "It names a block that is not on the page (\(name))."
        case .personsBlock: "It changes a block you wrote."
        case .unknownPlace(let name): "It names a place that is not on the page (\(name))."
        case .tooManyBlocks(let cap): "The page already has \(cap) machine blocks."
        case .unknownField(let field): "It uses a field this machine's facts do not have (\(field))."
        case .unknownValue(let field, let value): "No fact has \(field) \(value)."
        case .noCite: "It names nothing that its words or numbers rest on."
        case .unknownCite(let name): "It cites something that is not on the page or among the facts (\(name))."
        case .unevenGrid: "Its rows are not all as long as its header."
        case .formula(let text): "Its formula cannot be worked out (\(text))."
        }
    }
}

/// What a machine's blocks may name: the fields a view may filter and group by with the values facts have, the
/// columns a table may show, and the facts a text may cite.
public struct PageCatalog: Equatable, Sendable {
    public static let quoteColumn = "quote"
    public static let dayColumn = "day"

    /// What a fact shows in a column: the value of a field of the spec, its exact words, or its day.
    public static func value(of column: String, in item: Item) -> String {
        switch column {
        case quoteColumn: item.quote
        case dayColumn: item.day.description
        default: item[column]
        }
    }

    public var values: [String: Set<String>]
    public var columns: Set<String>
    public var facts: Set<Int64>

    public init(spec: HelperSpec, items: [Item]) {
        values = [:]
        for field in spec.fields {
            switch field.kind {
            case .choice, .computed, .member, .label:
                values[field.name] = Set(field.kind.fixedValues ?? []).union(items.map { $0[field.name] })
                    .subtracting([""])
            case .text, .date, .time, .objectRef: continue
            }
        }
        columns = Set(spec.fields.map(\.name)).union([Self.quoteColumn, Self.dayColumn])
        facts = Set(items.compactMap(\.id))
    }
}

/// An operation with what the gate decided. `operation` is nil for one that named a block the page does not have,
/// so that it could not even be formed.
public struct PageVerdict: Equatable, Sendable {
    public var operation: PageOperation?
    public var refusal: PageRefusal?

    public init(operation: PageOperation?, refusal: PageRefusal?) {
        self.operation = operation
        self.refusal = refusal
    }
}

/// The rules between a machine and a page, in code. It reads no meaning from words: it checks names against the
/// catalog and the page.
public struct PageGate: Sendable {
    public var catalog: PageCatalog
    public var blockCap: Int

    public init(catalog: PageCatalog, blockCap: Int = 8) {
        self.catalog = catalog
        self.blockCap = blockCap
    }

    /// The page with every allowed operation applied in order, and each operation's verdict. Several inserts at one
    /// place keep their order.
    public func apply(
        _ operations: [PageOperation], to page: MachinePage
    ) -> (page: MachinePage, verdicts: [PageVerdict]) {
        var page = page
        var lastPlaced: [PageBlockRef?: PageBlockRef] = [:]
        let verdicts = operations.map { operation in
            let refusal = refusal(for: operation, on: page)
            guard refusal == nil else { return PageVerdict(operation: operation, refusal: refusal) }
            switch operation {
            case .insert(let block, let after):
                let id = MachineBlockID()
                let anchor = lastPlaced[after] ?? after
                let index = anchor.flatMap { page.order.firstIndex(of: $0) }.map { $0 + 1 } ?? page.order.count
                page.order.insert(.machine(id), at: index)
                page.blocks[id] = block
                lastPlaced[after] = .machine(id)
            case .update(let id, let block): page.blocks[id] = block
            case .remove(let id):
                page.blocks[id] = nil
                page.order.removeAll { $0 == .machine(id) }
            }
            return PageVerdict(operation: operation, refusal: nil)
        }
        return (page, verdicts)
    }

    func refusal(for operation: PageOperation, on page: MachinePage) -> PageRefusal? {
        switch operation {
        case .insert(let block, let after):
            if let after, !page.order.contains(after) { return .unknownPlace(String(describing: after)) }
            if page.blocks.count >= blockCap { return .tooManyBlocks(blockCap) }
            return refusal(for: block, on: page)
        case .update(let id, let block):
            return page.blocks[id] == nil ? .unknownBlock(id.rawValue) : refusal(for: block, on: page)
        case .remove(let id): return page.blocks[id] == nil ? .unknownBlock(id.rawValue) : nil
        }
    }

    func refusal(for block: MachineBlock, on page: MachinePage) -> PageRefusal? {
        switch block {
        case .heading, .picker: return nil
        case .text(let text): return refusal(for: text.cites, on: page)
        case .facts(let view):
            for (field, wanted) in view.filters.sorted(by: { $0.key < $1.key }) {
                guard let known = catalog.values[field] else { return .unknownField(field) }
                if let value = wanted.first(where: { !known.contains($0) }) {
                    return .unknownValue(field: field, value: value)
                }
            }
            if let groupBy = view.groupBy, catalog.values[groupBy] == nil { return .unknownField(groupBy) }
            return view.columns.first { !catalog.columns.contains($0) }.map(PageRefusal.unknownField)
        case .grid(let grid):
            guard grid.rows.allSatisfy({ $0.count == grid.columns.count }) else { return .unevenGrid }
            for (row, values) in zip(grid.rows, grid.values) {
                if let failed = zip(row, values).first(where: { $0.1 == .failed }) { return .formula(failed.0) }
            }
            return refusal(for: grid.cites, on: page)
        }
    }

    /// Words and numbers must rest on something that can be erased: at least one cite, each a fact of the catalog,
    /// a paragraph on the page, or the request.
    private func refusal(for cites: [PageCite], on page: MachinePage) -> PageRefusal? {
        guard !cites.isEmpty else { return .noCite }
        for cite in cites {
            switch cite {
            case .fact(let id) where !catalog.facts.contains(id): return .unknownCite(String(id))
            case .note(let block) where !page.order.contains(.note(block)): return .unknownCite(block.rawValue)
            case .fact, .note, .request: continue
            }
        }
        return nil
    }
}
