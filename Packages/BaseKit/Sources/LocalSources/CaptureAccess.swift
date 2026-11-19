import Foundation
import WorkbenchCore

public enum ReadError: Error, Equatable {
    case denied(DenyReason)
    case unreadableStore
    case unsupportedSchema
}

extension CapturePolicyProvider {
    /// Asks the current policy for a grant, and throws the reason when it says no.
    public func grant(for kind: SourceKind, label: String? = nil, at now: Date) async throws -> CaptureGrant {
        switch try await currentPolicy().authorize(CaptureRequest(kind: kind, label: label), at: now) {
        case .allow(let grant): grant
        case .deny(let reason): throw ReadError.denied(reason)
        case .confirm: throw ReadError.denied(.privateMode)
        }
    }
}

extension ReadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .denied(.captureOff): "Capture is off."
        case .denied(.paused): "Capture is paused."
        case .denied(.privateMode): "Private mode is on."
        case .denied(.sourceSwitchedOff): "This source is switched off in Settings."
        case .denied(.labelDenied): "This chat is on your never-read list."
        case .denied(.labelNotAllowed): "This chat is not the one you chose."
        case .unreadableStore: "The app's local data could not be opened. Is the app installed and signed in?"
        case .unsupportedSchema: "The app's local data has a layout Workbench does not know. Update Workbench."
        }
    }
}
