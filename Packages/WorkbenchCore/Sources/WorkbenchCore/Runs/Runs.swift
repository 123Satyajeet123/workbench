import Foundation

public typealias RunID = Int64

/// One model call: what was asked of which model, what it cost and how it ended.
public struct Run: Sendable, Equatable, Identifiable {
    public enum Outcome: String, Sendable, CaseIterable {
        case running, done, failed
    }

    public var id: RunID
    public var task: String
    public var model: String
    /// A hash of the instructions and the schema: the prompt version.
    public var prompt: String
    public var inputBytes: Int
    public var startedAt: Date
    public var endedAt: Date?
    public var outcome: Outcome
    public var error: String?
    public var usage: Usage
    /// Entries the task kept and dropped from the answer. Nil until the task says.
    public var kept: Int?
    public var dropped: Int?
}

/// A model whose every call is a run in the store: the row is written before the input leaves the Mac and finished
/// with what came back.
public struct RecordedModel: Sendable {
    public let model: any StructuredModel
    let store: Store

    public init(_ model: any StructuredModel, store: Store) {
        self.model = model
        self.store = store
    }

    public func generate<T: Decodable & Sendable>(
        _ type: T.Type, schema: JSONSchema, task: String, instructions: String, input: String
    ) async throws -> (value: T, run: RunID) {
        let schemaText = try schema.jsonText
        let prompt = Digest.sha256(instructions + "\n" + schemaText)
        try store.keepPrompt(hash: prompt, task: task, instructions: instructions, schema: schemaText)
        let run = try store.beginRun(task: task, model: model.name, prompt: prompt, input: input)
        do {
            let answer = try await model.generate(type, schema: schema, instructions: instructions, input: input)
            try store.finishRun(run, model: answer.model, usage: answer.usage, error: nil)
            return (answer.value, run)
        } catch {
            try store.finishRun(run, model: model.name, usage: Usage(), error: error.localizedDescription)
            throw error
        }
    }
}

extension Store {
    func beginRun(task: String, model: String, prompt: String, input: String) throws -> RunID {
        try database.run(
            """
            INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, outcome) VALUES (?,?,?,?,?,?,'running')
            """,
            [
                .text(task), .text(model), .text(prompt), SQLValue(input.utf8.count), .text(Digest.sha256(input)),
                SQLValue(clock()),
            ])
    }

    func finishRun(_ id: RunID, model: String, usage: Usage, error: String?) throws {
        try database.run(
            """
            UPDATE run SET model = ?, ended_at = ?, outcome = ?, error = ?, input_tokens = ?, cache_read_tokens = ?,
                cache_write_tokens = ?, output_tokens = ?, cost_usd = ? WHERE id = ? AND outcome = 'running'
            """,
            [
                .text(model), SQLValue(clock()), .text(error == nil ? "done" : "failed"), SQLValue(error),
                SQLValue(usage.inputTokens), SQLValue(usage.cacheReadTokens), SQLValue(usage.cacheWriteTokens),
                SQLValue(usage.outputTokens), .real(usage.costUSD), .int(id),
            ])
    }

    /// How many entries the task kept from the run's answer, and how many failed its checks.
    public func recordYield(of run: RunID, kept: Int, dropped: Int) throws {
        try database.run(
            "UPDATE run SET kept = ?, dropped = ? WHERE id = ?", [SQLValue(kept), SQLValue(dropped), .int(run)])
    }

    /// A run still open when the app starts was cut off.
    public func closeInterruptedRuns() throws {
        try database.run(
            "UPDATE run SET outcome = 'failed', ended_at = ?, error = 'Workbench stopped during the run' WHERE outcome = 'running'",
            [SQLValue(clock())])
    }
}

extension Queries {
    public func runs(since start: Date = .distantPast) throws -> [Run] {
        try database.rows(
            """
            SELECT id, task, model, prompt, input_bytes, started_at, ended_at, outcome, error, input_tokens,
                cache_read_tokens, cache_write_tokens, output_tokens, cost_usd, kept, dropped
            FROM run WHERE started_at >= ? ORDER BY id DESC
            """, [SQLValue(start)]
        ).compactMap { row in
            guard let outcome = row[7].string.flatMap(Run.Outcome.init) else { return nil }
            return Run(
                id: row[0].integer ?? 0, task: row[1].string ?? "", model: row[2].string ?? "",
                prompt: row[3].string ?? "", inputBytes: Int(row[4].integer ?? 0),
                startedAt: row[5].date ?? .distantPast, endedAt: row[6].date, outcome: outcome, error: row[8].string,
                usage: Usage(
                    inputTokens: Int(row[9].integer ?? 0), cacheReadTokens: Int(row[10].integer ?? 0),
                    cacheWriteTokens: Int(row[11].integer ?? 0), outputTokens: Int(row[12].integer ?? 0),
                    costUSD: row[13].double ?? 0),
                kept: row[14].integer.map(Int.init), dropped: row[15].integer.map(Int.init))
        }
    }

    public func usage(since start: Date) throws -> Usage {
        try runs(since: start).map(\.usage).reduce(Usage(), +)
    }
}

/// The founder's judgement of one thing a model proposed. Marks give each task its precision.
public enum Mark: String, Codable, CaseIterable, Sendable {
    /// From the model, not yet seen by the founder.
    case proposed
    case confirmed, rejected
}
