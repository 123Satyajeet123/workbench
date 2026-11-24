import Foundation

@testable import WorkbenchCore

/// What one request to the composer produced in either arm, before the checks read it.
struct PageEvalCall {
    var proposal: PageProposal?
    /// Why the call produced no proposal; nil when it did.
    var failure: String?
    var reply: JSONValue?
    var wallSeconds = 0.0
    var runRowSeconds = 0.0
    var windowLines = 0
    var usage = Usage()
    var turns = 1
    var toolCalls: [String: Int] = [:]
    var refusedToolCalls = 0
    var toolErrors = 0
    var permissionDenials = 0
    var unfetchedNames = 0
    /// The handles the tools returned; the reply may name only these.
    var returnedHandles: Set<String> = []
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
