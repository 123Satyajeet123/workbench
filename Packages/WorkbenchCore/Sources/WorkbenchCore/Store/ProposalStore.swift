import Foundation
import GRDB

extension Store {
    public func saveProposals(_ result: Mochi.Result, grant: CaptureGrant) throws {
        try check(grant, kind: .screen)
        try writer.write { db in
            for proposal in result.proposals {
                try db.execute(
                    sql: """
                        INSERT INTO proposal(run_id, name, template, brief, why, view, evidence, created_at)
                        VALUES (?,?,?,?,?,?,?,?)
                        """,
                    arguments: [
                        proposal.run, proposal.name, proposal.template, proposal.brief, proposal.why, proposal.view,
                        try Coding.json(proposal.evidence), clock().stored,
                    ])
            }
            if let run = result.run {
                try Self.recordYield(db, of: run, kept: result.proposals.count, dropped: result.dropped)
            }
        }
    }

    public func decide(_ proposal: Int64, _ decision: Proposal.Decision) throws {
        try writer.write { db in
            try db.execute(
                sql: "INSERT INTO proposal_decision(proposal_id, decision, at) VALUES (?,?,?)",
                arguments: [proposal, decision.rawValue, clock().stored])
        }
    }
}

extension Queries {
    public func proposals() throws -> [Proposal] {
        try reader.read { db in
            try db.fetch(
                "proposal",
                "SELECT id, run_id, name, template, brief, why, evidence, decision, view FROM proposal_now ORDER BY id DESC",
                as: Proposal.init(row:))
        }
    }
}

extension Proposal {
    init(row: Row) throws {
        self.init(
            id: try row.optionalValue("id"), run: try row.value("run_id"), name: try row.value("name"),
            template: try row.value("template"), brief: try row.value("brief"), why: try row.value("why"),
            view: try row.value("view"), evidence: try row.json("evidence"), decision: try row.enumeration("decision"))
    }
}
