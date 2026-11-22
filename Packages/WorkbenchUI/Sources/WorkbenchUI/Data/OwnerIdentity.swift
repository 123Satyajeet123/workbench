import Foundation
import Kernel

/// Who owns what this Mac reads, as the Kernel names a person. The name is random and means nothing: it is minted once
/// per person, the first time it is needed, and kept in the Keychain beside the team keys, so deleting the store does
/// not change it and no two people share one. The roster (M6) must bind this name to the person's device keys: a key
/// names a device, and a person may have several.
enum OwnerIdentity {
    static let secretName = "owner.person"

    /// The stored owner. A new one is minted only when the store says there is none, and is added, never written over
    /// another: a store that fails to answer, or a second writer that was first, never changes the owner.
    static func person(secrets: SecretStore) throws -> PersonID {
        if let saved = try secrets.lookup(secretName) { return try PersonID(saved) }
        let minted = try PersonID("p-" + UUID().uuidString)
        if try secrets.create(minted.rawValue, as: secretName) { return minted }
        guard let stored = try secrets.lookup(secretName) else { throw Unavailable(cause: "the saved owner vanished") }
        return try PersonID(stored)
    }

    /// The owner, or why there is none. The app starts either way: only reading WhatsApp needs an owner.
    static func result(secrets: SecretStore) -> Result<PersonID, any Error> {
        Result { try person(secrets: secrets) }.mapError { Unavailable(cause: $0.localizedDescription) }
    }

    struct Unavailable: LocalizedError {
        let cause: String
        var errorDescription: String? {
            "Workbench could not open the name it keeps for you in the Keychain, so it reads no WhatsApp chat: \(cause)"
        }
    }
}
