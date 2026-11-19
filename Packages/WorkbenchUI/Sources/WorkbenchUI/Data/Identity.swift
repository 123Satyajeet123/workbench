import Foundation
import Observation
import WorkbenchCore

struct Identity: Codable, Equatable {
    var name: String

    static let empty = Identity(name: "")
    private static let stateKey = "identity"

    var hasName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static func load(from store: Store) throws -> Identity? {
        try store.queries.state(forKey: stateKey).map { try JSONDecoder().decode(Identity.self, from: Data($0.utf8)) }
    }

    func save(to store: Store) throws {
        let trimmed = Identity(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        try store.saveState(String(decoding: try JSONEncoder().encode(trimmed), as: UTF8.self), forKey: Self.stateKey)
    }
}

@Observable
final class IdentityModel {
    var identity: Identity { didSet { save() } }
    private(set) var saveError: (any Error)?
    @ObservationIgnored private let store: Store?

    init(store: Store? = nil) {
        self.store = store
        do {
            identity = try store.flatMap(Identity.load(from:)) ?? .empty
        } catch {
            identity = .empty
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
