import Foundation
import GRDB

/// What an erase of lines reaches, in two passes (research 86 §5).
///
/// Pass 1, the affected set: every node that the erased lines reach along `run_input` and `derivation`, to any depth.
/// Pass 2, the IN set: a node stays IN while a `supports` edge from a surviving premise holds it; a node with a `quotes`
/// edge from an erased line, or from a node that went OUT, holds words that must go, and a node whose every `supports`
/// edge comes from a gone premise goes OUT too. A node that is reached and stays IN keeps its place and loses the words a
/// model wrote. One query serves the preview and the erase.
struct EraseClosure: Sendable, Equatable {
    var lines: Set<Node>
    var reached: Set<Node>
    var out: Set<Node>

    func ids(ofKind kind: NodeKind) -> Set<DatabaseValue> {
        Set(reached.filter { $0.kind == kind && !lines.contains($0) }.map(\.id))
    }

    var items: Set<Int64> { Set(ids(ofKind: .item).compactMap { Int64.fromDatabaseValue($0) }) }

    /// Pass 2 over the edges into the reached nodes. Pure: it reads no store.
    static func resolve(lines: Set<Node>, reached: Set<Node>, links: [Link]) -> EraseClosure {
        let byNode = Dictionary(grouping: links, by: \.node)
        var out: Set<Node> = []
        var changed = true
        func isGone(_ node: Node) -> Bool { lines.contains(node) || out.contains(node) }
        while changed {
            changed = false
            for node in reached where !isGone(node) {
                let edges = byNode[node, default: []]
                let supports = edges.filter { $0.edge == .supports }
                let quotesWhatIsGone = edges.contains { $0.edge == .quotes && isGone($0.source) }
                let lostAllSupport = !supports.isEmpty && supports.allSatisfy { isGone($0.source) }
                if quotesWhatIsGone || lostAllSupport {
                    out.insert(node)
                    changed = true
                }
            }
        }
        return EraseClosure(lines: lines, reached: reached, out: out)
    }

    struct Link: Hashable, Sendable {
        var node: Node
        var source: Node
        var edge: Edge
    }
}

extension Store {
    /// The nodes reached from the rows the selection names (lines, or the snapshots of a web erase), with their edges, resolved. Reads only.
    static func closure(of lines: LineSelection, kind seedKind: NodeKind = .line, in db: Database) throws
        -> EraseClosure
    {
        let reach = reachingCTE(lines, seedKind)
        let reached = try Row.fetchAll(db, sql: "\(reach) SELECT kind, id FROM reach", arguments: lines.arguments)
            .compactMap(nodeInRow(kind: "kind", id: "id"))
        let links = try Row.fetchAll(
            db,
            sql: """
                \(reach) SELECT d.node_kind, d.node_id, d.from_kind, d.from_id, d.edge FROM reach
                JOIN derivation d ON d.node_kind = reach.kind AND d.node_id = reach.id
                """, arguments: lines.arguments
        ).compactMap { row -> EraseClosure.Link? in
            guard let node = nodeInRow(kind: "node_kind", id: "node_id")(row),
                let source = nodeInRow(kind: "from_kind", id: "from_id")(row),
                let edge = Edge(rawValue: row["edge"])
            else { return nil }
            return EraseClosure.Link(node: node, source: source, edge: edge)
        }
        let erased = try DatabaseValue.fetchAll(db, sql: lines.sql, arguments: lines.arguments).map {
            Node(seedKind, $0)
        }
        return EraseClosure.resolve(lines: Set(erased), reached: Set(reached), links: links)
    }

    private static func nodeInRow(kind: String, id: String) -> (Row) -> Node? {
        { row in
            NodeKind(rawValue: row[kind]).map { Node($0, row[id] as DatabaseValue) }
        }
    }

    /// Every node that the lines reach: a run through the input it was shown, any other node through the edges that
    /// name its premise. `UNION` drops a node that was reached before, so a path that meets itself ends.
    private static func reachingCTE(_ lines: LineSelection, _ seedKind: NodeKind) -> String {
        """
        WITH RECURSIVE reach(kind, id) AS (
            SELECT '\(seedKind.rawValue)', seed.* FROM (\(lines.sql)) seed
            UNION
            SELECT 'run', input.run_id FROM reach JOIN run_input input ON input.ref = reach.id AND input.kind =
                CASE reach.kind WHEN 'item' THEN 'fact' WHEN 'machine_block' THEN 'block' ELSE reach.kind END
            UNION
            SELECT d.node_kind, d.node_id FROM reach JOIN derivation d ON d.from_kind = reach.kind AND d.from_id = reach.id
        )
        """
    }

    /// Applies the closure: each node kind's redactor empties the words of its nodes, and flags those that went OUT.
    static func apply(_ closure: EraseClosure, in db: Database) throws {
        for redactor in Redactors.all {
            let ids = Array(closure.ids(ofKind: redactor.kind))
            guard !ids.isEmpty else { continue }
            let out = Set(closure.out.filter { $0.kind == redactor.kind }.map(\.id))
            for (wentOut, group) in [(true, ids.filter(out.contains)), (false, ids.filter { !out.contains($0) })]
            where !group.isEmpty {
                try redactor.redact(group, wentOut, db)
            }
        }
    }
}
