import Foundation

extension PageBlockRef {
    /// `note:<block>` or `machine:<block>`.
    var stored: String {
        switch self {
        case .note(let block): "note:\(block.rawValue)"
        case .machine(let block): "machine:\(block.rawValue)"
        }
    }

    init?(stored: String) {
        guard let colon = stored.firstIndex(of: ":") else { return nil }
        let name = String(stored[stored.index(after: colon)...])
        switch stored[..<colon] {
        case "note":
            guard let block = BlockID(name) else { return nil }
            self = .note(block)
        case "machine":
            guard let block = MachineBlockID(name) else { return nil }
            self = .machine(block)
        default: return nil
        }
    }
}

/// One change of a stored proposal. It names block ids only: the words are in the blocks, which the store keeps as
/// rows of their own.
public enum StoredOperation: Equatable, Sendable, Codable {
    /// A new block after `after` (a paragraph or a block of the page, or one inserted earlier in the same proposal), or
    /// last when `after` is nil.
    case insert(MachineBlockID, after: PageBlockRef?)
    /// A new block takes the place of a live one, which stays as history.
    case replace(MachineBlockID, with: MachineBlockID)
    case remove(MachineBlockID)

    private enum Key: String, CodingKey {
        case op, block, after, with
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        let block = try Self.block(try values.decode(String.self, forKey: .block), in: values)
        switch try values.decode(String.self, forKey: .op) {
        case "insert":
            var after: PageBlockRef?
            if let text = try values.decodeIfPresent(String.self, forKey: .after) {
                guard let place = PageBlockRef(stored: text) else {
                    throw DecodingError.dataCorruptedError(forKey: .after, in: values, debugDescription: text)
                }
                after = place
            }
            self = .insert(block, after: after)
        case "replace":
            self = .replace(block, with: try Self.block(try values.decode(String.self, forKey: .with), in: values))
        case "remove": self = .remove(block)
        case let other: throw DecodingError.dataCorruptedError(forKey: .op, in: values, debugDescription: other)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .insert(let block, let after):
            try values.encode("insert", forKey: .op)
            try values.encode(block.rawValue, forKey: .block)
            try values.encodeIfPresent(after?.stored, forKey: .after)
        case .replace(let old, let new):
            try values.encode("replace", forKey: .op)
            try values.encode(old.rawValue, forKey: .block)
            try values.encode(new.rawValue, forKey: .with)
        case .remove(let block):
            try values.encode("remove", forKey: .op)
            try values.encode(block.rawValue, forKey: .block)
        }
    }

    private static func block(_ name: String, in values: KeyedDecodingContainer<Key>) throws -> MachineBlockID {
        guard let block = MachineBlockID(name) else {
            throw DecodingError.dataCorruptedError(forKey: .block, in: values, debugDescription: name)
        }
        return block
    }
}

/// A proposal as the store keeps it: its operations by block id, and the blocks the operations bring in, each under
/// the id the store gave it.
struct StagedProposal: Sendable {
    var operations: [StoredOperation] = []
    var blocks: [(id: MachineBlockID, block: MachineBlock)] = []

    /// Gives each new block its id. Inserts at one place keep their order: each goes after the one before it.
    init(_ operations: [PageOperation]) {
        var lastPlaced: [PageBlockRef?: PageBlockRef] = [:]
        for operation in operations {
            let id = MachineBlockID()
            switch operation {
            case .insert(let block, let after):
                self.operations.append(.insert(id, after: lastPlaced[after] ?? after))
                lastPlaced[after] = .machine(id)
                blocks.append((id, block))
            case .update(let old, let block):
                self.operations.append(.replace(old, with: id))
                blocks.append((id, block))
            case .remove(let old): self.operations.append(.remove(old))
            }
        }
    }
}

extension PageProposal {
    /// The operations the gate allowed, in order.
    public var allowed: [PageOperation] { verdicts.compactMap { $0.refusal == nil ? $0.operation : nil } }
}
