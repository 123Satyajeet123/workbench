import Foundation
import GRDB

/// Which use a day's marks may serve. Dev marks may shape a prompt; held-out marks only judge one. The date alone
/// decides, so no later choice can move a day from one set to the other.
public enum EvalSplit: String, Sendable, CaseIterable {
    case dev
    case heldOut = "held_out"

    public static let heldOutTenths = 3

    public init(_ day: WorkDay) {
        let first = UInt8(Digest.sha256(day.description).prefix(2), radix: 16) ?? 0
        self = Int(first) % 10 < Self.heldOutTenths ? .heldOut : .dev
    }
}

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
    /// Audit answers of fully answered runs on held-out days only, in the order given: what the certificate is
    /// computed from.
    public var heldOutAudit: Certificate
    public var usage: Usage

    public var id: String { "\(task)|\(model)|\(prompt)" }

    /// Dev and held-out together: what the founder sees as "right so far". Never a basis to keep a prompt.
    public var all: Tally {
        Tally(confirmed: dev.confirmed + heldOut.confirmed, rejected: dev.rejected + heldOut.rejected)
    }
}

extension Store {
    func keepPrompt(hash: String, task: String, instructions: String, schema: String) throws {
        try writer.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO prompt(hash, task, instructions, schema, first_used) VALUES (?,?,?,?,?)",
                arguments: [hash, task, instructions, schema, clock().stored])
        }
    }
}

extension Queries {
    /// The versions of one task's prompt, oldest first.
    public func prompts(task: String) throws -> [PromptVersion] {
        try reader.read { db in
            try db.fetch(
                "prompt", "SELECT hash, instructions, first_used FROM prompt WHERE task = ? ORDER BY first_used, hash",
                [task]
            ) { row in
                PromptVersion(
                    hash: try row.value("hash"), task: task, number: 0, instructions: try row.value("instructions"),
                    firstUsed: try row.date("first_used"))
            }
        }
        .enumerated().map { offset, version in
            var numbered = version
            numbered.number = offset + 1
            return numbered
        }
    }

    /// One row per task, model and prompt, newest first. Each mark counts toward the split of the day it belongs to.
    /// All its statements read one snapshot.
    public func quality() throws -> [Quality] {
        try reader.read { db in
            let tallies = try Self.tallies(db)
            let (audits, certificates) = try Self.audits(db)
            let versions = try Self.promptNumbers(db)
            return try db.fetch(
                "run",
                """
                SELECT task, model, prompt, COUNT(*), SUM(COALESCE(kept, 0)), SUM(COALESCE(dropped, 0)),
                    SUM(input_tokens), SUM(cache_read_tokens), SUM(cache_write_tokens), SUM(output_tokens), SUM(cost_usd)
                FROM run WHERE outcome = 'done' GROUP BY task, model, prompt ORDER BY MAX(id) DESC
                """
            ) { row in
                let (task, model, prompt) = (
                    try row.value(0) as String, try row.value(1) as String, try row.value(2) as String
                )
                let key = Self.key(task, model, prompt)
                let split = tallies[key] ?? [:]
                return Quality(
                    task: task, model: model, prompt: prompt, version: versions[prompt], runs: try row.value(3),
                    kept: try row.value(4), dropped: try row.value(5), dev: split[.dev] ?? Tally(),
                    heldOut: split[.heldOut] ?? Tally(), audited: audits[key] ?? AuditEstimate(),
                    heldOutAudit: certificates[key] ?? Certificate(),
                    usage: Usage(
                        inputTokens: try row.value(6), cacheReadTokens: try row.value(7),
                        cacheWriteTokens: try row.value(8), outputTokens: try row.value(9),
                        costUSD: try row.value(10)))
            }
        }
    }

    /// An SQL condition on item rows: every audited item of the item's run has an answer, so the run counts whole.
    static func everyAuditAnswered(in item: String) -> String {
        """
        NOT EXISTS (SELECT 1 FROM item_mark waiting WHERE waiting.run_id = \(item).run_id
            AND waiting.asked_with IS NOT NULL AND waiting.state = 'proposed')
        """
    }

    private static func key(_ task: String, _ model: String, _ prompt: String) -> String {
        "\(task)|\(model)|\(prompt)"
    }

    private static func key(_ row: Row) throws -> String {
        key(try row.value(0), try row.value(1), try row.value(2))
    }

    private static func tallies(_ db: Database) throws -> [String: [EvalSplit: Tally]] {
        let marks = try db.fetch(
            "item_mark",
            """
            SELECT r.task, r.model, r.prompt, m.day, SUM(m.state = 'confirmed'), SUM(m.state = 'rejected')
            FROM run r JOIN item_mark m ON m.run_id = r.id
            WHERE r.outcome = 'done' GROUP BY r.task, r.model, r.prompt, m.day
            """
        ) { row in
            (
                key: try key(row), split: EvalSplit(try row.workDay(3)), confirmed: try row.value(4) as Int,
                rejected: try row.value(5) as Int
            )
        }
        var tallies: [String: [EvalSplit: Tally]] = [:]
        for mark in marks {
            tallies[mark.key, default: [:]][mark.split, default: Tally()].confirmed += mark.confirmed
            tallies[mark.key, default: [:]][mark.split, default: Tally()].rejected += mark.rejected
        }
        return tallies
    }

    private static func audits(_ db: Database) throws -> ([String: AuditEstimate], [String: Certificate]) {
        let answers = try db.fetch(
            "item_mark",
            """
            SELECT r.task, r.model, r.prompt, m.asked_with, m.state, m.day, m.run_id
            FROM run r JOIN item_mark m ON m.run_id = r.id
            WHERE r.outcome = 'done' AND m.asked_with IS NOT NULL AND m.state <> 'proposed'
                AND \(everyAuditAnswered(in: "m"))
            ORDER BY (SELECT MAX(id) FROM mark WHERE mark.item_id = m.id)
            """
        ) { row in
            (
                key: try key(row), chance: try row.value(3) as Double,
                right: try row.enumeration(4) as Mark == .confirmed,
                split: EvalSplit(try row.workDay(5)), run: try row.value(6) as Int64
            )
        }
        var audits: [String: AuditEstimate] = [:]
        var certificates: [String: Certificate] = [:]
        for answer in answers {
            let weight = 1 / answer.chance
            audits[answer.key, default: AuditEstimate()].marks += 1
            audits[answer.key, default: AuditEstimate()].weight += weight
            if answer.right { audits[answer.key, default: AuditEstimate()].rightWeight += weight }
            if answer.split == .heldOut {
                certificates[answer.key, default: Certificate()].answers.append(
                    Certificate.Answer(wrong: !answer.right, chance: answer.chance, run: answer.run))
            }
        }
        return (audits, certificates)
    }

    /// Each prompt's number: its place among its task's prompts, oldest first.
    private static func promptNumbers(_ db: Database) throws -> [String: Int] {
        let numbers = try db.fetch(
            "prompt",
            "SELECT hash, (SELECT COUNT(*) FROM prompt q WHERE q.task = p.task AND (q.first_used < p.first_used OR (q.first_used = p.first_used AND q.hash <= p.hash))) FROM prompt p"
        ) { row in (hash: try row.value(0) as String, number: try row.value(1) as Int) }
        return Dictionary(numbers.map { ($0.hash, $0.number) }, uniquingKeysWith: { first, _ in first })
    }
}
