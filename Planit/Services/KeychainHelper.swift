import Foundation
import Security

/// macOS Keychain-backed storage for sensitive data (OAuth tokens, credentials).
/// All related values are stored as a single JSON blob per group to minimize Keychain prompts.
enum KeychainHelper {
    private static let service = "com.oy.planit"

    // MARK: - Generic single-item API (internal)

    @discardableResult
    private static func saveItem(account: String, data: Data) -> Bool {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Update existing item (also migrates kSecAttrAccessible to current policy)
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        // Only add if item genuinely does not exist; other errors (locked, permission) are real failures
        guard updateStatus == errSecItemNotFound else { return false }
        var addQuery = lookup
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private static func loadItem(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    @discardableResult
    private static func deleteItem(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Auth Tokens (single Keychain entry)
    // Stores accessToken + refreshToken together to avoid multiple prompts.

    private static let tokenAccount = "planit.auth.tokens"

    struct AuthTokens: Codable {
        var accessToken: String?
        var refreshToken: String?
        var tokenExpiry: Double?   // timeIntervalSince1970
        var userEmail: String?
    }

    static func loadAuthTokens() -> AuthTokens {
        guard let data = loadItem(account: tokenAccount),
              let tokens = try? JSONDecoder().decode(AuthTokens.self, from: data) else {
            return AuthTokens()
        }
        return tokens
    }

    @discardableResult
    static func saveAuthTokens(_ tokens: AuthTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        return saveItem(account: tokenAccount, data: data)
    }

    @discardableResult
    static func deleteAuthTokens() -> Bool {
        deleteItem(account: tokenAccount)
    }

    // MARK: - OAuth Credentials (single Keychain entry)

    private static let credentialsAccount = "planit.auth.credentials"

    struct OAuthCredentials: Codable {
        var clientID: String
        var clientSecret: String
    }

    static func loadCredentials() -> OAuthCredentials? {
        guard let data = loadItem(account: credentialsAccount),
              let creds = try? JSONDecoder().decode(OAuthCredentials.self, from: data) else {
            return nil
        }
        return creds
    }

    @discardableResult
    static func saveCredentials(_ creds: OAuthCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(creds) else { return false }
        return saveItem(account: credentialsAccount, data: data)
    }

    // MARK: - Migration

    /// One-time migration: old file-based tokens → Keychain, old individual Keychain items → consolidated.
    static func migrateIfNeeded() {
        migrateFromFileStorage()
        migrateFromIndividualKeychainItems()
    }

    private static func migrateFromFileStorage() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let tokenDir = support.appendingPathComponent("Planit/tokens", isDirectory: true)
        guard FileManager.default.fileExists(atPath: tokenDir.path) else { return }

        var tokens = loadAuthTokens()
        var filesToDelete: [URL] = []
        let fileMap: [(String, WritableKeyPath<AuthTokens, String?>)] = [
            ("planit_accessToken",  \.accessToken),
            ("planit_refreshToken", \.refreshToken),
            ("planit_userEmail",    \.userEmail),
        ]
        for (fileName, kp) in fileMap {
            let path = tokenDir.appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: path), let value = String(data: data, encoding: .utf8) {
                tokens[keyPath: kp] = value
                filesToDelete.append(path)
            }
        }
        let expiryPath = tokenDir.appendingPathComponent("planit_tokenExpiry")
        if let data = try? Data(contentsOf: expiryPath),
           let value = String(data: data, encoding: .utf8), let t = Double(value) {
            tokens.tokenExpiry = t
            filesToDelete.append(expiryPath)
        }
        // Only delete source files after successful Keychain save
        if !filesToDelete.isEmpty && saveAuthTokens(tokens) {
            filesToDelete.forEach { try? FileManager.default.removeItem(at: $0) }
        }

        let contents = (try? FileManager.default.contentsOfDirectory(atPath: tokenDir.path)) ?? []
        if contents.isEmpty { try? FileManager.default.removeItem(at: tokenDir) }
    }

    private static func migrateFromIndividualKeychainItems() {
        // If consolidated item already exists, skip
        if loadItem(account: tokenAccount) != nil &&
           loadItem(account: credentialsAccount) != nil { return }

        // Pull legacy individual items
        func legacyLoad(_ key: String) -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        // Collect which legacy keys exist and merge into consolidated tokens
        var tokens = loadAuthTokens()
        var legacyTokenKeys: [String] = []
        if let v = legacyLoad("planit.accessToken")  { tokens.accessToken  = v; legacyTokenKeys.append("planit.accessToken") }
        if let v = legacyLoad("planit.refreshToken") { tokens.refreshToken = v; legacyTokenKeys.append("planit.refreshToken") }
        if let v = legacyLoad("planit.userEmail")    { tokens.userEmail    = v; legacyTokenKeys.append("planit.userEmail") }
        if let s = legacyLoad("planit.tokenExpiry"), let t = Double(s) {
            tokens.tokenExpiry = t
            legacyTokenKeys.append("planit.tokenExpiry")
        }

        // Only save and delete if we actually found legacy tokens to migrate
        if !legacyTokenKeys.isEmpty && saveAuthTokens(tokens) {
            legacyTokenKeys.forEach { deleteItem(account: $0) }
        }

        // Credentials: only migrate if both clientId and clientSecret exist
        if let id = legacyLoad("planit.oauth.clientId"),
           let secret = legacyLoad("planit.oauth.clientSecret"),
           saveCredentials(OAuthCredentials(clientID: id, clientSecret: secret)) {
            deleteItem(account: "planit.oauth.clientId")
            deleteItem(account: "planit.oauth.clientSecret")
        }
    }
}
