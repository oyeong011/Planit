import Foundation
import Security

/// macOS Keychain-backed storage for sensitive data (OAuth tokens, etc.)
enum KeychainHelper {
    private static let service = "com.oy.planit"

    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Migrate old file-based tokens to Keychain (one-time)
    static func migrateFromFileStorage() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let tokenDir = support.appendingPathComponent("Planit/tokens", isDirectory: true)
        guard FileManager.default.fileExists(atPath: tokenDir.path) else { return }

        let keyMap = [
            "planit_accessToken": "planit.accessToken",
            "planit_refreshToken": "planit.refreshToken",
            "planit_tokenExpiry": "planit.tokenExpiry",
            "planit_userEmail": "planit.userEmail",
        ]

        for (fileName, keychainKey) in keyMap {
            let filePath = tokenDir.appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: filePath),
               let value = String(data: data, encoding: .utf8) {
                save(key: keychainKey, value: value)
                try? FileManager.default.removeItem(at: filePath)
            }
        }

        // Remove the tokens directory if empty
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: tokenDir.path)) ?? []
        if contents.isEmpty {
            try? FileManager.default.removeItem(at: tokenDir)
        }
    }
}
