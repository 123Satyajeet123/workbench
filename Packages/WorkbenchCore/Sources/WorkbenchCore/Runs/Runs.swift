import Foundation
import GRDB

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

/// What a run was asked and what it answered, kept so the run can be replayed.
public struct RunText: Sendable, Equatable {
    public var input: String
    /// The reply as the model gave it. Nil while the run is open, and when it failed.
    public var reply: String?
    /// The consent kinds the input holds: a delete of one of them removes this text.
    public var kinds: Set<SourceKind>
    /// The input also holds text whose consent kind is not known: every source delete removes this text.
    public var holdsUnknown = false

    /// How an unknown kind is written among the stored kinds.
    static let unknownKind = "unknown"
}

/// A model whose every call is a run in the store: the row and the input are written before the input leaves the Mac
/// and finished with what came back. `holding` names the consent kinds the input holds, and `holdingUnknown` says
/// that it also holds text of an unknown kind.
public struct RecordedModel: Sendable {
    public let model: any StructuredModel
    let store: Store

    public init(_ model: any StructuredModel, store: Store) {
        self.model = model
        self.store = store
    }

    public func generate<T: Decodable & Sendable>(
        _ type: T.Type, schema: JSONSchema, task: String, instructions: String, input: String,
        holding kinds: Set<SourceKind>, holdingUnknown: Bool = false
    ) async throws -> (value: T, run: RunID) {
        let schemaText = try schema.jsonText
        let prompt = Digest.sha256(instructions + "\n" + schemaText)
        try store.keepPrompt(hash: prompt, task: task, instructions: instructions, schema: schemaText)
        let run = try store.beginRun(
            task: task, model: model.name, prompt: prompt, input: input, kinds: kinds, holdsUnknown: holdingUnknown)
        do {
            let answer = try await model.generate(type, schema: schema, instructions: instructions, input: input)
            guard schema.accepts(json: answer.reply) else {
                throw StructuredModelError.invalidReply("the reply does not fit the schema")
            }
            try store.finishRun(run, model: answer.model, usage: answer.usage, reply: answer.reply, error: nil)
            return (answer.value, run)
        } catch {
            try store.finishRun(
                run, model: model.name, usage: Usage(), reply: nil, error: error.localizedDescription)
            throw error
        }
    }
}

extension Store {
    func beginRun(
        task: String, model: String, prompt: String, input: String, kinds: Set<SourceKind>, holdsUnknown: Bool = false
    ) throws -> RunID {
        let names = kinds.map(\.rawValue).sorted() + (holdsUnknown ? [RunText.unknownKind] : [])
        return try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, outcome) VALUES (?,?,?,?,?,?,'running')
                    """,
                arguments: [task, model, prompt, input.utf8.count, Digest.sha256(input), clock().stored])
            let run = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO run_text(run_id, input, kinds) VALUES (?,?,?)",
                arguments: [run, input, try Coding.json(names)])
            return run
        }
    }

    func finishRun(_ id: RunID, model: String, usage: Usage, reply: String?, error: String?) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    UPDATE run SET model = ?, ended_at = ?, outcome = ?, error = ?, input_tokens = ?, cache_read_tokens = ?,
                        cache_write_tokens = ?, output_tokens = ?, cost_usd = ? WHERE id = ? AND outcome = 'running'
                    """,
                arguments: [
                    model, clock().stored, error == nil ? "done" : "failed", error, usage.inputTokens,
                    usage.cacheReadTokens, usage.cacheWriteTokens, usage.outputTokens, usage.costUSD, id,
                ])
            try db.execute(sql: "UPDATE run_text SET reply = ? WHERE run_id = ?", arguments: [reply, id])
        }
    }

    /// How many entries the task kept from the run's answer, and how many failed its checks.
    public func recordYield(of run: RunID, kept: Int, dropped: Int) throws {
        try writer.write { db in try Self.recordYield(db, of: run, kept: kept, dropped: dropped) }
    }

    static func recordYield(_ db: Database, of run: RunID, kept: Int, dropped: Int) throws {
        try db.execute(sql: "UPDATE run SET kept = ?, dropped = ? WHERE id = ?", arguments: [kept, dropped, run])
    }

    /// A run still open when the app starts was cut off.
    public func closeInterruptedRuns() throws {
        try writer.write { db in
            try db.execute(
                sql:
                    "UPDATE run SET outcome = 'failed', ended_at = ?, error = 'Workbench stopped during the run' WHERE outcome = 'running'",
                arguments: [clock().stored])
        }
    }
}

extension Queries {
    public func runs(since start: Date = .distantPast) throws -> [Run] {
        try reader.read { db in
            try db.fetch(
                "run",
                """
                SELECT id, task, model, prompt, input_bytes, started_at, ended_at, outcome, error, input_tokens,
                    cache_read_tokens, cache_write_tokens, output_tokens, cost_usd, kept, dropped
                FROM run WHERE started_at >= ? ORDER BY id DESC
                """, [start.stored], as: Run.init(row:))
        }
    }

    /// What a run was asked and answered, to replay it. Nil once a privacy delete or the retention removed it.
    public func runText(of run: RunID) throws -> RunText? {
        try reader.read { db in
            try db.fetch(
                "run_text", "SELECT input, reply, kinds FROM run_text WHERE run_id = ?", [run], as: RunText.init(row:)
            ).first
        }
    }

    public func usage(since start: Date) throws -> Usage {
        try runs(since: start).map(\.usage).reduce(Usage(), +)
    }
}

extension Run {
    init(row: Row) throws {
        self.init(
            id: try row.value("id"), task: try row.value("task"), model: try row.value("model"),
            prompt: try row.value("prompt"), inputBytes: try row.value("input_bytes"),
            startedAt: try row.date("started_at"), endedAt: try row.optionalDate("ended_at"),
            outcome: try row.enumeration("outcome"), error: try row.optionalValue("error"),
            usage: Usage(
                inputTokens: try row.value("input_tokens"), cacheReadTokens: try row.value("cache_read_tokens"),
                cacheWriteTokens: try row.value("cache_write_tokens"), outputTokens: try row.value("output_tokens"),
                costUSD: try row.value("cost_usd")),
            kept: try row.optionalValue("kept"), dropped: try row.optionalValue("dropped"))
    }
}

extension RunText {
    init(row: Row) throws {
        let names: [String] = try row.json("kinds")
        self.init(
            input: try row.value("input"), reply: try row.optionalValue("reply"),
            kinds: Set(
                try names.filter { $0 != RunText.unknownKind }.map { name in
                    guard let kind = SourceKind(rawValue: name) else { throw StoredValueError("kinds") }
                    return kind
                }), holdsUnknown: names.contains(RunText.unknownKind))
    }
}

/// The founder's judgement of one thing a model proposed. Marks give each task its precision.
public enum Mark: String, Codable, CaseIterable, Sendable {
    /// From the model, not yet seen by the founder.
    case proposed
    case confirmed, rejected
}
