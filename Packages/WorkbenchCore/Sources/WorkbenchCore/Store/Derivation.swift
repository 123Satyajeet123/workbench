import Foundation
import GRDB

/// The kinds of thing that a derivation edge joins. A node kind that is also a source kind (`item`, `machineBlock`,
/// `workProduct`) can be a premise of a later node. The kinds of the first row are the roots: words that a source gave,
/// which an edge starts from and no edge ends at.
enum NodeKind: String, Sendable, CaseIterable {
    case line, snapshot, activity, recording
    case mailPart = "mail_part"
    case newsArticle = "news_article"
    case run
    case item
    case itemEvent = "item_event"
    case summary
    case machineBlock = "machine_block"
    case pageProposal = "page_proposal"
    case proposal
    case action
    case workEvent = "work_event"
    case machineDecision = "machine_decision"
    case workProduct = "work_product"
    case claimCite = "claim_cite"
    case judgeVerdict = "judge_verdict"
    case productMark = "product_mark"
}

/// A thing in the derivation graph: its kind, and its id as the table keeps it (a line id, a row number, a text key).
struct Node: Hashable, Sendable {
    var kind: NodeKind
    var id: DatabaseValue

    init(_ kind: NodeKind, _ id: some DatabaseValueConvertible) {
        self.kind = kind
        self.id = id.databaseValue
    }

    static func line(_ lineID: Data) -> Node { Node(.line, lineID) }
}

/// What a node holds of its source: `quotes` says it holds words copied from it; `supports` says it rests on it.
enum Edge: String, Sendable {
    case quotes, supports
}

struct Source: Hashable, Sendable {
    var node: Node
    var edge: Edge

    static func quotes(_ node: Node) -> Source { Source(node: node, edge: .quotes) }
    static func supports(_ node: Node) -> Source { Source(node: node, edge: .supports) }
}

/// A node with every source it was made from, and the run and rule that made it.
struct Derivation: Sendable, Equatable {
    var node: Node
    var sources: [Source]
    var run: RunID?
    var rule: String
}

extension Store {
    /// The one place an edge enters `derivation`. Every node that lives outside a run calls it in the transaction that
    /// writes the node. An edge that exists is not written again, so a repeat adds nothing. `replacing` first removes the
    /// edges of a node that a new write replaces.
    static func derive(_ derivations: [Derivation], replacing: Bool = false, at now: Date, in db: Database) throws {
        for derivation in derivations {
            if replacing {
                try db.execute(
                    sql: "DELETE FROM derivation WHERE node_kind = ? AND node_id = ?",
                    arguments: [derivation.node.kind.rawValue, derivation.node.id])
            }
            for source in derivation.sources {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO derivation(node_kind, node_id, from_kind, from_id, edge, run_id, rule,
                            recorded_at) VALUES (?,?,?,?,?,?,?,?)
                        """,
                    arguments: [
                        derivation.node.kind.rawValue, derivation.node.id, source.node.kind.rawValue,
                        source.node.id, source.edge.rawValue, derivation.run, derivation.rule, now.stored,
                    ])
            }
        }
    }
}
