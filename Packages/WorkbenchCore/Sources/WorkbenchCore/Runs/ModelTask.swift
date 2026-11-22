protocol ModelTask: Sendable {
    associatedtype Reply: Decodable & Sendable

    static var task: String { get }
    static var instructions: String { get }
    static var schema: JSONSchema { get }
    var model: RecordedModel { get }
}

extension ModelTask {
    func ask(
        _ input: String, holding kinds: Set<SourceKind>, holdingUnknown: Bool = false
    ) async throws -> (value: Reply, run: RunID) {
        try await model.generate(
            Reply.self, schema: Self.schema, task: Self.task, instructions: Self.instructions, input: input,
            holding: kinds, holdingUnknown: holdingUnknown)
    }
}
