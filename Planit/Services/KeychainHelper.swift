import Foundation
import Security

/// macOS Keychain-backed storage for sensitive data (OAuth tokens, credentials).
/// All related values are stored as a single JSON blob per group to minimize Keychain prompts.
/// In-memory cache prevents repeated Keychain reads per session.
enum KeychainHelper {
    private static let service = "com.oy.planit"

    // MARK: - In-memory cache (avoids repeated Keychain prompts per session)

    private static var tokensCache: AuthTokens?
    private static var credentialsCache: OAuthCredentials?
    private static var apiKeyCache: [String: String] = [:]   // account → value

    // MARK: - Generic single-item API (internal)

    @discardableResult
    private static func saveItem(account: String, data: Data) -> Bool {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }

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

    private static let tokenAccount = "planit.auth.tokens"

    struct AuthTokens: Codable {
        var accessToken: String?
        var refreshToken: String?
        var tokenExpiry: Double?   // timeIntervalSince1970
        var userEmail: String?
    }

    static func loadAuthTokens() -> AuthTokens {
        if let cached = tokensCache { return cached }
        guard let data = loadItem(account: tokenAccount),
              let tokens = try? JSONDecoder().decode(AuthTokens.self, from: data) else {
            return AuthTokens()
        }
        tokensCache = tokens
        return tokens
    }

    @discardableResult
    static func saveAuthTokens(_ tokens: AuthTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        if saveItem(account: tokenAccount, data: data) {
            tokensCache = tokens   // 캐시 갱신
            return true
        }
        return false
    }

    @discardableResult
    static func deleteAuthTokens() -> Bool {
        tokensCache = nil
        return deleteItem(account: tokenAccount)
    }

    // MARK: - OAuth Credentials (single Keychain entry)

    private static let credentialsAccount = "planit.auth.credentials"

    struct OAuthCredentials: Codable {
        var clientID: String
        var clientSecret: String
    }

    static func loadCredentials() -> OAuthCredentials? {
        if let cached = credentialsCache { return cached }
        guard let data = loadItem(account: credentialsAccount),
              let creds = try? JSONDecoder().decode(OAuthCredentials.self, from: data) else {
            return nil
        }
        credentialsCache = creds
        return creds
    }

    @discardableResult
    static func saveCredentials(_ creds: OAuthCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(creds) else { return false }
        if saveItem(account: credentialsAccount, data: data) {
            credentialsCache = creds   // 캐시 갱신
            return true
        }
        return false
    }

    // MARK: - API Keys (Claude API, etc.)

    static func loadAPIKey(account: String) -> String? {
        if let cached = apiKeyCache[account] { return cached }
        guard let data = loadItem(account: account),
              let key = String(data: data, encoding: .utf8) else { return nil }
        apiKeyCache[account] = key
        return key
    }

    @discardableResult
    static func saveAPIKey(_ key: String, account: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        if saveItem(account: account, data: data) {
            apiKeyCache[account] = key
            return true
        }
        return false
    }

    @discardableResult
    static func deleteAPIKey(account: String) -> Bool {
        apiKeyCache.removeValue(forKey: account)
        return deleteItem(account: account)
    }

    // MARK: - Migration (one-time, guarded by UserDefaults flag)

    private static let migrationDoneKey = "planit.keychain.migrationDone.v2"

    /// One-time migration: file-based tokens → Keychain, individual items → consolidated.
    static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationDoneKey) else { return }
        migrateFromFileStorage()
        migrateFromIndividualKeychainItems()
        UserDefaults.standard.set(true, forKey: migrationDoneKey)
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
        if !filesToDelete.isEmpty && saveAuthTokens(tokens) {
            filesToDelete.forEach { try? FileManager.default.removeItem(at: $0) }
        }

        let contents = (try? FileManager.default.contentsOfDirectory(atPath: tokenDir.path)) ?? []
        if contents.isEmpty { try? FileManager.default.removeItem(at: tokenDir) }
    }

    private static func migrateFromIndividualKeychainItems() {
        // Already consolidated — skip
        if loadItem(account: tokenAccount) != nil &&
           loadItem(account: credentialsAccount) != nil { return }

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

        var tokens = loadAuthTokens()
        var legacyTokenKeys: [String] = []
        if let v = legacyLoad("planit.accessToken")  { tokens.accessToken  = v; legacyTokenKeys.append("planit.accessToken") }
        if let v = legacyLoad("planit.refreshToken") { tokens.refreshToken = v; legacyTokenKeys.append("planit.refreshToken") }
        if let v = legacyLoad("planit.userEmail")    { tokens.userEmail    = v; legacyTokenKeys.append("planit.userEmail") }
        if let s = legacyLoad("planit.tokenExpiry"), let t = Double(s) {
            tokens.tokenExpiry = t
            legacyTokenKeys.append("planit.tokenExpiry")
        }
        if !legacyTokenKeys.isEmpty && saveAuthTokens(tokens) {
            legacyTokenKeys.forEach { deleteItem(account: $0) }
        }

        if let id = legacyLoad("planit.oauth.clientId"),
           let secret = legacyLoad("planit.oauth.clientSecret"),
           saveCredentials(OAuthCredentials(clientID: id, clientSecret: secret)) {
            deleteItem(account: "planit.oauth.clientId")
            deleteItem(account: "planit.oauth.clientSecret")
        }
    }
}
