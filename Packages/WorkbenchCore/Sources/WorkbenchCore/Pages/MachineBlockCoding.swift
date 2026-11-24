import Foundation

/// The kinds of block a machine may put on a page, as the store names them.
public enum MachineBlockKind: String, CaseIterable, Codable, Sendable {
    case heading, text, facts, grid, picker
}

extension MachineBlock {
    public var kind: MachineBlockKind {
        switch self {
        case .heading: .heading
        case .text: .text
        case .facts: .facts
        case .grid: .grid
        case .picker: .picker
        }
    }

    /// What the block names as the ground of its words: the cites it carries, and, for a block that carries none of
    /// its own but holds words a model wrote (a heading, the title of a view), the request that asked for it.
    var grounds: [PageCite] {
        switch self {
        case .heading, .facts: [.request]
        case .text(let text): text.cites
        case .grid(let grid): grid.cites
        case .picker: []
        }
    }

    /// Whether the block has a label of its own, joined from what it rests on. A view has none: each row of it is
    /// checked by its own label. A picker holds no words.
    var hasLabel: Bool {
        switch kind {
        case .heading, .text, .grid: true
        case .facts, .picker: false
        }
    }

    /// The block with the words a model wrote taken out. It keeps its kind, its cites, and the settings of a view.
    var emptied: MachineBlock {
        switch self {
        case .heading: return .heading("")
        case .text(let text): return .text(CitedText(text: "", cites: text.cites))
        case .facts(var view):
            view.title = ""
            return .facts(view)
        case .grid(let grid): return .grid(Grid(title: "", columns: [], rows: [], cites: grid.cites))
        case .picker: return self
        }
    }
}

extension PageCite {
    var fact: Int64? {
        if case .fact(let id) = self { id } else { nil }
    }

    /// `fact:12`, `note:<block>` or `request`.
    var stored: String {
        switch self {
        case .fact(let id): "fact:\(id)"
        case .note(let block): "note:\(block.rawValue)"
        case .request: "request"
        }
    }

    init?(stored: String) {
        if stored == "request" {
            self = .request
            return
        }
        guard let colon = stored.firstIndex(of: ":") else { return nil }
        let value = String(stored[stored.index(after: colon)...])
        switch stored[..<colon] {
        case "fact":
            guard let id = Int64(value) else { return nil }
            self = .fact(id)
        case "note":
            guard let block = BlockID(value) else { return nil }
            self = .note(block)
        default: return nil
        }
    }
}

/// The JSON of a block in `machine_block.spec`: one object with a `kind` and the fields of that kind, each named here
/// and nowhere else.
extension MachineBlock: Codable {
    private enum Key: String, CodingKey {
        case kind, text, title, cites, filters, groupBy, layout, columns, rows, source, countBy, show, order, limit
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        switch try values.decode(MachineBlockKind.self, forKey: .kind) {
        case .heading: self = .heading(try values.decode(String.self, forKey: .text))
        case .text:
            self = .text(
                CitedText(
                    text: try values.decode(String.self, forKey: .text), cites: try Self.cites(in: values)))
        case .facts:
            self = .facts(
                FactsView(
                    title: try values.decode(String.self, forKey: .title),
                    filters: try values.decode([String: [String]].self, forKey: .filters),
                    groupBy: try values.decodeIfPresent(String.self, forKey: .groupBy),
                    layout: try values.decode(FactsView.Layout.self, forKey: .layout),
                    columns: try values.decode([String].self, forKey: .columns),
                    countBy: try values.decodeIfPresent(String.self, forKey: .countBy),
                    show: try values.decodeIfPresent(FactsView.Show.self, forKey: .show) ?? .all,
                    order: try values.decodeIfPresent(FactsView.Order.self, forKey: .order) ?? .stored,
                    limit: try values.decodeIfPresent(Int.self, forKey: .limit)))
        case .grid:
            self = .grid(
                Grid(
                    title: try values.decode(String.self, forKey: .title),
                    columns: try values.decode([String].self, forKey: .columns),
                    rows: try values.decode([[String]].self, forKey: .rows), cites: try Self.cites(in: values)))
        case .picker: self = .picker(try values.decode(PickerKind.self, forKey: .source))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        try values.encode(kind, forKey: .kind)
        switch self {
        case .heading(let text): try values.encode(text, forKey: .text)
        case .text(let text):
            try values.encode(text.text, forKey: .text)
            try values.encode(text.cites.map(\.stored), forKey: .cites)
        case .facts(let view):
            try values.encode(view.title, forKey: .title)
            try values.encode(view.filters, forKey: .filters)
            try values.encodeIfPresent(view.groupBy, forKey: .groupBy)
            try values.encode(view.layout, forKey: .layout)
            try values.encode(view.columns, forKey: .columns)
            try values.encodeIfPresent(view.countBy, forKey: .countBy)
            if view.show != .all { try values.encode(view.show, forKey: .show) }
            if view.order != .stored { try values.encode(view.order, forKey: .order) }
            try values.encodeIfPresent(view.limit, forKey: .limit)
        case .grid(let grid):
            try values.encode(grid.title, forKey: .title)
            try values.encode(grid.columns, forKey: .columns)
            try values.encode(grid.rows, forKey: .rows)
            try values.encode(grid.cites.map(\.stored), forKey: .cites)
        case .picker(let kind): try values.encode(kind, forKey: .source)
        }
    }

    private static func cites(in values: KeyedDecodingContainer<Key>) throws -> [PageCite] {
        try values.decode([String].self, forKey: .cites).map { text in
            guard let cite = PageCite(stored: text) else {
                throw DecodingError.dataCorruptedError(forKey: .cites, in: values, debugDescription: text)
            }
            return cite
        }
    }
}

extension FactsView.Layout: Codable {}
extension FactsView.Show: Codable {}
extension FactsView.Order: Codable {}
extension PickerKind: Codable {}
