import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct ContextSpecTests {
    @Test func aLabelMustNotBeEmptyAndTheModelIsToldToReuseTheList() {
        let reader = HelperReader(spec: .context, model: RecordedModel(ScriptedModel("{}"), store: try! makeStore()))
        #expect(reader.instructions.contains("- topic: reuse a name from the topics list when it fits"))
        #expect(Set(HelperSpec.context.views.keys) == ["table", "by kind", "by topic", "by stance"])
        #expect(HelperSpec.context.view == .grouped(by: "topic"))
    }
}
