/// One model call, named: its run task, its instructions, its reply schema and the model that answers. Every call of
/// a recorded model goes through `ask`, so a prompt is described in one place and the run row is written the same way.
protocol ModelTask: Sendable {
    associatedtype Reply: Decodable & Sendable

    var task: String { get }
    var instructions: String { get }
    var schema: JSONSchema { get }
    var model: RecordedModel { get }
}

/// A task whose text never changes between calls. Its prompt is static, so tests and callers can name it without a value.
protocol FixedModelTask: ModelTask {
    static var task: String { get }
    static var instructions: String { get }
    static var schema: JSONSchema { get }
}

extension FixedModelTask {
    var task: String { Self.task }
    var instructions: String { Self.instructions }
    var schema: JSONSchema { Self.schema }
}

extension ModelTask {
    func ask(
        _ input: String, holding kinds: Set<SourceKind>, holdingUnknown: Bool = false, window: [WindowLine] = []
    ) async throws -> (value: Reply, run: RunID) {
        try await model.generate(
            Reply.self, schema: schema, task: task, instructions: instructions, input: input, holding: kinds,
            holdingUnknown: holdingUnknown, window: window)
    }
}
