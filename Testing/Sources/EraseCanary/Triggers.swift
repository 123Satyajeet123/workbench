import Foundation

@testable import WorkbenchCore

/// A way a person or the app erases: each one reaches the same erase path of the store from another door.
enum Trigger: String, CaseIterable {
    case revoke = "sender revokes the message"
    case allowListOff = "chat taken off the allow list"
    case deleteKind = "delete of one kind of source"
    case retention = "retention cutoff"

    /// The words that must be in no byte of the store after the trigger, by the name `Words.all` gives them.
    var gone: Set<String> {
        switch self {
        case .revoke: ["canary"]
        case .allowListOff: ["canary", "same chat"]
        case .deleteKind: ["canary", "same chat", "other chat"]
        case .retention: ["canary", "same chat", "mail", "call", "page"]
        }
    }

    /// Whether the facts that rest on the line stay, flagged and emptied, or go with their source's kind.
    var keepsFacts: Bool { self == .revoke || self == .allowListOff }

    /// Whether the recording folder of the call must be gone.
    var removesRecordings: Bool { self == .retention }

    func fire(_ scene: Scene) async throws {
        let store = scene.store
        switch self {
        case .revoke:
            try scene.record(
                [try Scene.groupTombstone(chat: Scene.chatA, stanza: "A1", at: scene.now)], chat: Scene.chatA)
        case .allowListOff:
            scene.policy.allowList[.whatsapp] = [Scene.chatB]
            try store.savePolicy(scene.policy)
            try store.eraseEvidence(.grant(kind: .whatsapp, label: Scene.chatA))
        case .deleteKind:
            try store.delete(.kind(.whatsapp, before: nil))
        case .retention:
            try store.delete(.everything(before: scene.now.addingTimeInterval(-20 * Scene.day)))
        }
    }
}
