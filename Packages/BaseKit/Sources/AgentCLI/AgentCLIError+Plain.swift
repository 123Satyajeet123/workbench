import Foundation

extension AgentCLIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInstalled(let kind):
            "The \(kind.rawValue) command-line tool is not installed on this Mac. Install it, sign in, then try again."
        case .unsafePlan(let reason): "Workbench stopped a model call that was not safe: \(reason)"
        case .timedOut: "The model did not answer in time."
        }
    }
}
