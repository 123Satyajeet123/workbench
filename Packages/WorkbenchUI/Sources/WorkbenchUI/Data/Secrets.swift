import Foundation
import Security

/// Where Workbench keeps a secret the founder typed: the founder's own Anthropic API key. Never the store, never a log.
protocol SecretStore: Sendable {
    func read(_ name: String) -> String?
    func save(_ value: String, as name: String) throws
    func remove(_ name: String) throws
}

/// The macOS Keychain, as a generic password of this app.
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
