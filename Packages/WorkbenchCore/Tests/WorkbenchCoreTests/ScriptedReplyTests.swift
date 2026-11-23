import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct ReplySchemaTests {
    private let schema = JSONSchema.object([
        .init("kind", .enumeration(["a", "b"])), .init("cite", .integer), .init("ok", .boolean),
        .init("cites", .array(.integer)),
    ])

    @Test func aReplyFitsOnlyWithEveryPropertyOfTheRightTypeAndNoOther() {
        #expect(schema.accepts(json: #"{"kind":"a","cite":3,"ok":true,"cites":[1,2]}"#))
        #expect(!schema.accepts(json: #"{"kind":"a","cite":3,"ok":true}"#), "missing property")
        #expect(!schema.accepts(json: #"{"kind":"a","cite":3,"ok":true,"cites":[],"extra":1}"#), "extra property")
        #expect(!schema.accepts(json: #"{"kind":"c","cite":3,"ok":true,"cites":[]}"#), "value outside the enum")
        #expect(!schema.accepts(json: #"{"kind":"a","cite":3.5,"ok":true,"cites":[]}"#), "fraction for an integer")
        #expect(!schema.accepts(json: #"{"kind":"a","cite":3,"ok":1,"cites":[]}"#), "number for a boolean")
        #expect(!schema.accepts(json: #"{"kind":"a","cite":true,"ok":true,"cites":[]}"#), "boolean for an integer")
        #expect(!schema.accepts(json: "not json"))
    }

    @Test func aRunWhoseReplyDoesNotFitFailsAndSaysSo() async throws {
        let store = try makeStore()
        let model = RecordedModel(ScriptedModel(#"{"kind":"c","cite":3,"ok":true,"cites":[]}"#), store: store)
        await #expect(throws: StructuredModelError.invalidReply("the reply does not fit the schema")) {
            _ = try await model.generate(
                [String: JSONValue].self, schema: schema, task: "t", instructions: "", input: "", holding: [])
        }
        #expect(try store.queries.runs().first?.outcome == .failed)
    }
}
