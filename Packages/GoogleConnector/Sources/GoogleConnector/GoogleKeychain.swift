import Foundation
import Security

struct GoogleKeychain: Sendable {
    static let appService = "com.hizen.workbench.google"

    let service: String

    init(service: String = GoogleKeychain.appService) {
        self.service = service
    }

    func save(_ data: Data, account: String) throws {
        let status = SecItemUpdate(
            match(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            try check(
                SecItemAdd(match(account: account).merging([kSecValueData as String: data]) { $1 } as CFDictionary, nil)
            )
        } else {
            try check(status)
        }
    }

    func read(account: String) throws -> Data? {
        var result: CFTypeRef?
        let query = match(account: account).merging([kSecReturnData as String: true]) { $1 }
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        return result as? Data
    }

    func accounts() throws -> [String] {
        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        let items = result as? [[String: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    func delete(account: String) throws {
        let status = SecItemDelete(match(account: account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func match(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw GoogleError.keychain(status: status) }
    }
}
