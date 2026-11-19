import Foundation

extension Store {
    /// Keeps Mochi's proposals from one run, and the run's yield. Reading Mochi's input needs screen consent, because
    /// the blocks come from screen sessions; the grant is asked after the model ran.
    public func saveProposals(_ result: Mochi.Result, grant: CaptureGrant) throws {
        try check(grant, kind: .screen)
        try database.transaction {
            for proposal in result.proposals {
                try database.run(
                    "INSERT INTO proposal(run_id, name, template, brief, why, evidence, created_at) VALUES (?,?,?,?,?,?,?)",
                    [
                        .int(proposal.run), .text(proposal.name), .text(proposal.template), .text(proposal.brief),
                        .text(proposal.why), .text(try Coding.json(proposal.evidence)), SQLValue(clock()),
                    ])
            }
            if let run = result.run { try recordYield(of: run, kept: result.proposals.count, dropped: result.dropped) }
        }
    }

    /// Decisions are history: the latest is the proposal's state.
    public func decide(_ proposal: Int64, _ decision: Proposal.Decision) throws {
        try database.run(
            "INSERT INTO proposal_decision(proposal_id, decision, at) VALUES (?,?,?)",
            [.int(proposal), .text(decision.rawValue), SQLValue(clock())])
    }
}

extension Queries {
    /// Every proposal, newest first.
    public func proposals() throws -> [Proposal] {
        try database.rows(
            "SELECT id, run_id, name, template, brief, why, evidence, decision FROM proposal_now ORDER BY id DESC"
        ).compactMap { row in
            guard let decision = row[7].string.flatMap(Proposal.Decision.init),
                let evidence = try? Coding.value([Int64].self, from: row[6].string ?? "")
            else { return nil }
            return Proposal(
                id: row[0].integer, run: row[1].integer ?? 0, name: row[2].string ?? "", template: row[3].string ?? "",
                brief: row[4].string ?? "", why: row[5].string ?? "", evidence: evidence, decision: decision)
        }
    }
}
