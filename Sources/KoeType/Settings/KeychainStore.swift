import Foundation
import Security

enum KeychainError: Error { case status(OSStatus) }

enum KeychainStore {
    private static let service = "jp.caruvistar.koetype"
    private static let account = "openai-api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func readAPIKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saving an empty string deletes the stored key.
    static func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
            return
        }
        let value = [kSecValueData as String: Data(trimmed.utf8)]
        var status = SecItemUpdate(baseQuery as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery.merging(value) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }
}
