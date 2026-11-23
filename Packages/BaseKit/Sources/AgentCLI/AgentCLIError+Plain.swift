import Foundation

extension AgentCLIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInstalled(let kind):
            "The \(kind.rawValue) command-line tool is not installed on this Mac. Install it, sign in, then try again."
        case .noAPIKey:
            "Billing is set to your own API key, and no key is saved. Add it in Settings › General, or bill your Claude plan."
        case .unsafePlan(let reason): "Workbench stopped a model call that was not safe: \(reason)"
        case .timedOut: "The model did not answer in time."
        case .planLimit(let resetsAt):
            "Your Claude plan is at its limit."
                + (resetsAt.map { " It resets at \($0.formatted(date: .abbreviated, time: .shortened))." } ?? "")
        }
    }
}
