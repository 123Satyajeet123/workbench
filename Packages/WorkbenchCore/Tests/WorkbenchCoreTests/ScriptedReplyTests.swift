import Foundation
import Testing

@testable import WorkbenchCore

/// The test model holds scripted replies to the schema, as the CLIs hold real ones.
@Suite struct ScriptedReplyTests {
    private let schema = JSONSchema.object([
        .init("kind", .enumeration(["a", "b"])), .init("cite", .integer), .init("ok", .boolean),
        .init("cites", .array(.integer)),
    ])

    private func fits(_ json: String) throws -> Bool {
        schema.accepts(try JSONSerialization.jsonObject(with: Data(json.utf8)))
    }

    @Test func aReplyFitsOnlyWithEveryPropertyOfTheRightTypeAndNoOther() throws {
        #expect(try fits(#"{"kind":"a","cite":3,"ok":true,"cites":[1,2]}"#))
        #expect(try !fits(#"{"kind":"a","cite":3,"ok":true}"#), "missing property")
        #expect(try !fits(#"{"kind":"a","cite":3,"ok":true,"cites":[],"extra":1}"#), "extra property")
        #expect(try !fits(#"{"kind":"c","cite":3,"ok":true,"cites":[]}"#), "value outside the enum")
        #expect(try !fits(#"{"kind":"a","cite":3.5,"ok":true,"cites":[]}"#), "fraction for an integer")
        #expect(try !fits(#"{"kind":"a","cite":3,"ok":1,"cites":[]}"#), "number for a boolean")
        #expect(try !fits(#"{"kind":"a","cite":true,"ok":true,"cites":[]}"#), "boolean for an integer")
    }

    @Test func theTestModelRefusesAReplyThatDoesNotFit() async throws {
        let model = ScriptedModel(#"{"kind":"c","cite":3,"ok":true,"cites":[]}"#)
        await #expect(throws: StructuredModelError.invalidReply("the scripted reply does not fit the schema")) {
            _ = try await model.generate(
                [String: JSONValue].self, schema: schema, instructions: "", input: "")
        }
    }
}
