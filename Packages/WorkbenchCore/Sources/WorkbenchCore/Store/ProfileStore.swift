import Foundation
import GRDB

extension Store {
    static let profileKey = "workspace.profile"

    public func saveProfile(_ profile: WorkspaceProfile) throws {
        try saveState(try Coding.json(profile), forKey: Self.profileKey)
    }

    /// Once per store, as it opens: a store that already holds prompts gets `WorkspaceProfile.continuity`, so the
    /// prompts it keeps rendering are the ones it earned trust on; any other store starts with an empty profile.
    static func startProfile(_ writer: DatabasePool, at now: Date) throws {
        try writer.write { db in
            guard try String.fetchOne(db, sql: "SELECT value FROM state WHERE key = ?", arguments: [profileKey]) == nil
            else { return }
            let holdsPrompts = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM prompt)") ?? false
            let profile = holdsPrompts ? WorkspaceProfile.continuity : WorkspaceProfile()
            try upsertState(db, key: profileKey, value: try Coding.json(profile), savedAt: now)
        }
    }
}

extension Queries {
    /// The workspace profile; empty for a store that has none.
    public func profile() throws -> WorkspaceProfile {
        try state(forKey: Store.profileKey).map { try Coding.value(WorkspaceProfile.self, from: $0) }
            ?? WorkspaceProfile()
    }
}

extension RecordedModel {
    /// The profile the prompts of this model's calls are written for. A store that cannot give one is not open, and
    /// the call that follows fails on it.
    var profile: WorkspaceProfile { (try? store.queries.profile()) ?? WorkspaceProfile() }
}
