import Foundation
import Observation
import WorkbenchCore

struct Identity: Codable, Equatable {
    var name: String

    static let empty = Identity(name: "")
    private static let stateKey = StateKey<Identity>.json("identity")

    var hasName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func greeting(at date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return hasName ? "\(part), \(name)" : part
    }

    static func load(from store: Store) throws -> Identity? {
        try stateKey.load(from: store)
    }

    func save(to store: Store) throws {
        let trimmed = Identity(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        try Self.stateKey.save(trimmed, to: store)
    }
}

@Observable
final class IdentityModel {
    var identity: Identity { didSet { save() } }
    /// What the person is and which languages their sources use: the words the machines' instructions are written in.
    private(set) var workspace = WorkspaceProfile()
    private(set) var saveError: (any Error)?
    @ObservationIgnored private let store: Store?

    init(store: Store? = nil) {
        self.store = store
        do {
            identity = try store.flatMap(Identity.load(from:)) ?? .empty
            workspace = try store?.queries.profile() ?? WorkspaceProfile()
        } catch {
            identity = .empty
            saveError = error
        }
    }

    /// Saves on the person's act only: new words change every machine's instructions, so each earns its trust again.
    func saveWorkspace(_ profile: WorkspaceProfile) {
        guard let store, profile != workspace else { return }
        do {
            try store.saveProfile(profile)
            workspace = profile
            saveError = nil
        } catch {
            saveError = error
        }
    }

    private func save() {
        guard let store else { return }
        do {
            try identity.save(to: store)
            saveError = nil
        } catch {
            saveError = error
        }
    }
}
