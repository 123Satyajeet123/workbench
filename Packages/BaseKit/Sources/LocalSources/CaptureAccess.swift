import Foundation
import WorkbenchCore

public enum ReadError: Error, Equatable {
    case denied(DenyReason)
    case notPermitted
    case storeMissing
    case unreadableStore
    case unsupportedSchema
    /// The file does not start with the SQLite header: it is encrypted, damaged or not a database.
    case notADatabase
    /// A group with no readable member list: who could read its messages is unknown.
    case audienceUnknown
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
        case .notPermitted:
            "macOS does not let Workbench read the app's data yet. Turn on Workbench in System Settings › Privacy & Security › Full Disk Access, then quit and reopen Workbench."
        case .storeMissing: "The app's data is not on this Mac. Install the app and sign in, then try again."
        case .unreadableStore: "The app's local data could not be opened. Is the app installed and signed in?"
        case .unsupportedSchema: "The app's local data has a layout Workbench does not know. Update Workbench."
        case .notADatabase: "The app's local data is not in a format Workbench can read. Update Workbench."
        case .audienceUnknown: "Workbench cannot tell who is in this group, so it did not read it."
        }
    }
}
