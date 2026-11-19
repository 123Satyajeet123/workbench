import Foundation

/// Which use a day's marks may serve. Dev marks may shape a prompt; held-out marks only judge one. The date alone
/// decides, so no later choice can move a day from one set to the other.
public enum EvalSplit: String, Sendable, CaseIterable {
    case dev
    case heldOut = "held_out"

    /// Out of ten days, this many are held out.
    public static let heldOutTenths = 3

    public init(_ day: WorkDay) {
        let first = UInt8(Digest.sha256(day.description).prefix(2), radix: 16) ?? 0
        self = Int(first) % 10 < Self.heldOutTenths ? .heldOut : .dev
    }
}

/// The founder's marks on one set of days.
public struct Tally: Sendable, Equatable {
    public var confirmed = 0
    public var rejected = 0

    public init(confirmed: Int = 0, rejected: Int = 0) {
        self.confirmed = confirmed
        self.rejected = rejected
    }

    public var marked: Int { confirmed + rejected }
    /// Confirmed over marked. Nil while nothing is marked.
    public var precision: Double? { marked == 0 ? nil : Double(confirmed) / Double(marked) }
}

/// A helper's precision from audit marks only: answers on items the app picked at random. Each answer weighs one
/// over the chance its item had, so it stands for every item of its reading; voluntary marks never count here.
public struct AuditEstimate: Sendable, Equatable {
    public var marks = 0
    public var rightWeight = 0.0
    public var weight = 0.0

    public init(marks: Int = 0, rightWeight: Double = 0, weight: Double = 0) {
        self.marks = marks
        self.rightWeight = rightWeight
        self.weight = weight
    }

    /// Nil while no picked item is answered.
    public var precision: Double? { weight == 0 ? nil : rightWeight / weight }
}

/// One version of a task's instructions, named by its hash and numbered in the order it was first used.
public struct PromptVersion: Sendable, Equatable {
    public var hash: String
    public var task: String
    public var number: Int
    public var instructions: String
    public var firstUsed: Date
}

/// How well one prompt version on one model did at one task: what it proposed and what the founder marked, with dev
/// and held-out days apart.
public struct Quality: Sendable, Equatable, Identifiable {
    public var task: String
    public var model: String
    public var prompt: String
    /// Nil for runs made before prompts were kept.
    public var version: Int?
    public var runs: Int
    public var kept: Int
    public var dropped: Int
    public var dev: Tally
    public var heldOut: Tally
    public var audited: AuditEstimate
    /// Audit answers on held-out days only: what the certificate is computed from.
    public var heldOutAudit: Certificate
    public var usage: Usage

    public var id: String { "\(task)|\(model)|\(prompt)" }

    /// Dev and held-out together: what the founder sees as "right so far". Never a basis to keep a prompt.
    public var all: Tally {
        Tally(confirmed: dev.confirmed + heldOut.confirmed, rejected: dev.rejected + heldOut.rejected)
    }
}

extension Store {
    /// Keeps the text of a prompt version the first time it is used.
    func keepPrompt(hash: String, task: String, instructions: String, schema: String) throws {
        try database.run(
            "INSERT OR IGNORE INTO prompt(hash, task, instructions, schema, first_used) VALUES (?,?,?,?,?)",
            [.text(hash), .text(task), .text(instructions), .text(schema), SQLValue(clock())])
    }
}

extension Queries {
    /// The versions of one task's prompt, oldest first.
    public func prompts(task: String) throws -> [PromptVersion] {
        try database.rows(
            "SELECT hash, instructions, first_used FROM prompt WHERE task = ? ORDER BY first_used, hash",
            [.text(task)]
        ).enumerated().map { offset, row in
            PromptVersion(
                hash: row[0].string ?? "", task: task, number: offset + 1, instructions: row[1].string ?? "",
                firstUsed: row[2].date ?? .distantPast)
        }
    }

    /// One row per task, model and prompt, newest first. Each mark counts toward the split of the day it belongs to.
    public func quality() throws -> [Quality] {
        let marks = try database.rows(
            """
            SELECT r.task, r.model, r.prompt, m.day, SUM(m.state = 'confirmed'), SUM(m.state = 'rejected')
            FROM run r JOIN item_mark m ON m.run_id = r.id
            WHERE r.outcome = 'done' GROUP BY r.task, r.model, r.prompt, m.day
            """)
        var tallies: [String: [EvalSplit: Tally]] = [:]
        for row in marks {
            let key = "\(row[0].string ?? "")|\(row[1].string ?? "")|\(row[2].string ?? "")"
            let split = row[3].string.flatMap { WorkDay($0) }.map(EvalSplit.init) ?? .dev
            tallies[key, default: [:]][split, default: Tally()].confirmed += Int(row[4].integer ?? 0)
            tallies[key, default: [:]][split, default: Tally()].rejected += Int(row[5].integer ?? 0)
        }
        var audits: [String: AuditEstimate] = [:]
        var certificates: [String: Certificate] = [:]
        for row in try database.rows(
            """
            SELECT r.task, r.model, r.prompt, m.asked_with, m.state, m.day FROM run r JOIN item_mark m ON m.run_id = r.id
            WHERE r.outcome = 'done' AND m.asked_with IS NOT NULL AND m.state <> 'proposed'
            """)
        {
            let key = "\(row[0].string ?? "")|\(row[1].string ?? "")|\(row[2].string ?? "")"
            let weight = 1 / (row[3].double ?? 1)
            audits[key, default: AuditEstimate()].marks += 1
            audits[key, default: AuditEstimate()].weight += weight
            let right = row[4].string == Mark.confirmed.rawValue
            if right { audits[key, default: AuditEstimate()].rightWeight += weight }
            if row[5].string.flatMap({ WorkDay($0) }).map(EvalSplit.init) == .heldOut {
                certificates[key, default: Certificate(answers: 0, wrong: 0)].answers += 1
                if !right { certificates[key, default: Certificate(answers: 0, wrong: 0)].wrong += 1 }
            }
        }
        let versions = try database.rows(
            "SELECT hash, (SELECT COUNT(*) FROM prompt q WHERE q.task = p.task AND (q.first_used < p.first_used OR (q.first_used = p.first_used AND q.hash <= p.hash))) FROM prompt p"
        ).reduce(into: [String: Int]()) { $0[$1[0].string ?? ""] = Int($1[1].integer ?? 0) }
        return try database.rows(
            """
            SELECT task, model, prompt, COUNT(*), SUM(COALESCE(kept, 0)), SUM(COALESCE(dropped, 0)),
                SUM(input_tokens), SUM(cache_read_tokens), SUM(cache_write_tokens), SUM(output_tokens), SUM(cost_usd)
            FROM run WHERE outcome = 'done' GROUP BY task, model, prompt ORDER BY MAX(id) DESC
            """
        ).map { row in
            let (task, model, prompt) = (row[0].string ?? "", row[1].string ?? "", row[2].string ?? "")
            let split = tallies["\(task)|\(model)|\(prompt)"] ?? [:]
            return Quality(
                task: task, model: model, prompt: prompt, version: versions[prompt], runs: Int(row[3].integer ?? 0),
                kept: Int(row[4].integer ?? 0), dropped: Int(row[5].integer ?? 0), dev: split[.dev] ?? Tally(),
                heldOut: split[.heldOut] ?? Tally(), audited: audits["\(task)|\(model)|\(prompt)"] ?? AuditEstimate(),
                heldOutAudit: certificates["\(task)|\(model)|\(prompt)"] ?? Certificate(answers: 0, wrong: 0),
                usage: Usage(
                    inputTokens: Int(row[6].integer ?? 0), cacheReadTokens: Int(row[7].integer ?? 0),
                    cacheWriteTokens: Int(row[8].integer ?? 0), outputTokens: Int(row[9].integer ?? 0),
                    costUSD: row[10].double ?? 0))
        }
    }
}
