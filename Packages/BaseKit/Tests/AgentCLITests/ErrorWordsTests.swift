import Foundation
import Testing

@testable import AgentCLI

struct ErrorWordsTests {
    @Test func everyAgentErrorReadsAsAPlainSentence() {
        #expect(AgentCLIError.timedOut.localizedDescription == "The model did not answer in time.")
        #expect(AgentCLIError.unsafePlan("an API key").localizedDescription.contains("an API key"))
        #expect(!AgentCLIError.timedOut.localizedDescription.contains("AgentCLIError"))
    }
}
