import Foundation
import Security
import Synchronization

/// Where Workbench keeps a secret the founder typed: the founder's own Anthropic API key. Never the store, never a log.
protocol SecretStore: Sendable {
    func read(_ name: String) -> String?
    /// The secret, or nil when there is none. Any other failure throws: a store that cannot answer has not said "none".
    func lookup(_ name: String) throws -> String?
    /// Adds a secret that does not exist yet. False when one exists: it is never overwritten.
    func create(_ value: String, as name: String) throws -> Bool
    func save(_ value: String, as name: String) throws
    func remove(_ name: String) throws
}

/// Secrets held in memory for the life of the process.
final class MemorySecrets: SecretStore, Sendable {
    let values = Mutex<[String: String]>([:])

    func read(_ name: String) -> String? { values.withLock { $0[name] } }
    func lookup(_ name: String) throws -> String? { values.withLock { $0[name] } }
    func create(_ value: String, as name: String) throws -> Bool {
        values.withLock { values in
            guard values[name] == nil else { return false }
            values[name] = value
            return true
        }
    }
    func save(_ value: String, as name: String) throws { values.withLock { $0[name] = value } }
    func remove(_ name: String) throws { values.withLock { $0[name] = nil } }
}

struct KeychainSecrets: SecretStore {
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "The Keychain refused: \(SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)")."
        }
    }

    private let service = "com.hizen.workbench"

    private func query(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
    }

    func read(_ name: String) -> String? {
        var query = query(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func lookup(_ name: String) throws -> String? {
        var query = query(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw Failure(status: status) }
        return String(data: data, encoding: .utf8)
    }

    func create(_ value: String, as name: String) throws -> Bool {
        var query = query(name)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return true
    }

    /// Updates the item in place, or adds it: the old key stays until the new one is stored.
    func save(_ value: String, as name: String) throws {
        let data = Data(value.utf8)
        var status = SecItemUpdate(query(name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = query(name)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    func remove(_ name: String) throws {
        let status = SecItemDelete(query(name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
