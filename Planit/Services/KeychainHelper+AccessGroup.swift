import Foundation
import Security

// MARK: - KeychainHelper + App Group 공유
//
// macOS Calen(com.oy.planit)과 iOS CaleniOS(com.oy.planit.ios)가 **동일 Keychain 아이템**을
// 공유하기 위한 access group 래퍼.
//
// 설계 원칙:
//  - 기존 `KeychainHelper.swift` 본체는 **건드리지 않는다** — macOS 기존 동작 회귀 위험 제로.
//  - 이 파일은 신규 공유 경로만 다룬다: access group + data protection keychain.
//  - One-shot migration 함수(`migrateToSharedGroup`)가 default-group에 남아있는
//    아이템을 shared group으로 복사 + 원본 삭제한다.
//
// iOS 빌드 시 `keychain-access-groups` 엔타이틀먼트에 `$(AppIdentifierPrefix)group.com.oy.planit`,
// macOS(향후 Calen.app 리빌드 시) 엔타이틀먼트에도 동일 값이 있어야 한다.
// NOTE (RELEASE 팀장): `kSecAttrAccessGroup` 값은 런타임에 "Team ID.group.com.oy.planit" 형태의
// 풀 프리픽스가 필요할 수 있다. 지금은 plain `group.com.oy.planit`로 두고, 실제 배포 시
// `$(AppIdentifierPrefix)group.com.oy.planit`을 주입하도록 RELEASE 팀장이 수정.
enum KeychainSharedAccessGroup {
    /// App Group identifier. RELEASE 팀장이 실제 배포 빌드에서 Team ID prefix를 붙여야 할 수 있다.
    static let identifier: String = "group.com.oy.planit"
    /// Data Protection Keychain (iCloud Keychain이 아닌 로컬 보호 키체인) 사용 여부.
    /// iOS에서는 반드시 true — generic password가 App Group과 함께 동작하려면 필요.
    /// macOS 14+는 Data Protection Keychain을 지원 (sandboxed가 아니어도 작동).
    static let useDataProtectionKeychain: Bool = true

    // MARK: - Service / accounts (KeychainHelper와 동일 값 재사용)
    fileprivate static let service = "com.oy.planit"
    fileprivate static let tokenAccount = "planit.auth.tokens"
    fileprivate static let credentialsAccount = "planit.auth.credentials"
    fileprivate static let fileIntegrityKeyAccount = "planit.file-integrity.key.v1"
    fileprivate static let migrationDoneKey = "planit.keychain.sharedGroup.migrationDone.v1"
}

/// Shared-group Keychain 래퍼. 저장/로드/삭제 모두 access group을 명시한다.
enum SharedKeychainHelper {
    // MARK: - Core ops

    @discardableResult
    static func saveItem(account: String, data: Data) -> Bool {
        var lookup = baseQuery(account: account)
        // update 쿼리에서는 `kSecUseDataProtectionKeychain`/`kSecAttrAccessGroup`이
        // 있어야 shared group의 기존 아이템을 올바르게 지정할 수 있다.
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: false,  // iCloud Keychain 동기화 방지
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        // add
        lookup[kSecValueData as String] = data
        lookup[kSecAttrSynchronizable as String] = false
        lookup[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(lookup as CFDictionary, nil) == errSecSuccess
    }

    static func loadItem(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    @discardableResult
    static func deleteItem(account: String) -> Bool {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainSharedAccessGroup.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: KeychainSharedAccessGroup.identifier,
        ]
        if KeychainSharedAccessGroup.useDataProtectionKeychain {
            q[kSecUseDataProtectionKeychain as String] = true
        }
        return q
    }

    // MARK: - Typed wrappers (KeychainHelper 구조체와 직렬화 호환)

    static func loadAuthTokens() -> KeychainHelper.AuthTokens? {
        guard let data = loadItem(account: KeychainSharedAccessGroup.tokenAccount) else { return nil }
        return try? JSONDecoder().decode(KeychainHelper.AuthTokens.self, from: data)
    }

    @discardableResult
    static func saveAuthTokens(_ tokens: KeychainHelper.AuthTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(tokens) else { return false }
        return saveItem(account: KeychainSharedAccessGroup.tokenAccount, data: data)
    }

    @discardableResult
    static func deleteAuthTokens() -> Bool {
        deleteItem(account: KeychainSharedAccessGroup.tokenAccount)
    }

    static func loadCredentials() -> KeychainHelper.OAuthCredentials? {
        guard let data = loadItem(account: KeychainSharedAccessGroup.credentialsAccount) else { return nil }
        return try? JSONDecoder().decode(KeychainHelper.OAuthCredentials.self, from: data)
    }

    @discardableResult
    static func saveCredentials(_ creds: KeychainHelper.OAuthCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(creds) else { return false }
        return saveItem(account: KeychainSharedAccessGroup.credentialsAccount, data: data)
    }

    // MARK: - One-shot migration
    //
    // 기존 macOS 앱은 default access group(= Team ID prefix만) 에 저장했다.
    // App Group 공유를 켜고 나면 새 위치로 옮겨야 iOS가 읽을 수 있다.
    // `UserDefaults` 플래그로 1회만 실행한다.
    //
    // 성공 조건: 기존 아이템이 없거나, 복사 후 shared group에서 읽혀야 플래그 set.
    @discardableResult
    static func migrateToSharedGroup() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: KeychainSharedAccessGroup.migrationDoneKey) { return true }

        var okAll = true

        // 1) Auth tokens
        if let legacyData = legacyLoadItem(account: KeychainSharedAccessGroup.tokenAccount) {
            if saveItem(account: KeychainSharedAccessGroup.tokenAccount, data: legacyData) {
                legacyDeleteItem(account: KeychainSharedAccessGroup.tokenAccount)
            } else {
                okAll = false
            }
        }

        // 2) OAuth credentials
        if let legacyData = legacyLoadItem(account: KeychainSharedAccessGroup.credentialsAccount) {
            if saveItem(account: KeychainSharedAccessGroup.credentialsAccount, data: legacyData) {
                legacyDeleteItem(account: KeychainSharedAccessGroup.credentialsAccount)
            } else {
                okAll = false
            }
        }

        // 3) File integrity key (macOS only — iOS에서는 없음)
        if let legacyData = legacyLoadItem(account: KeychainSharedAccessGroup.fileIntegrityKeyAccount) {
            if saveItem(account: KeychainSharedAccessGroup.fileIntegrityKeyAccount, data: legacyData) {
                legacyDeleteItem(account: KeychainSharedAccessGroup.fileIntegrityKeyAccount)
            } else {
                okAll = false
            }
        }

        if okAll {
            defaults.set(true, forKey: KeychainSharedAccessGroup.migrationDoneKey)
        }
        return okAll
    }

    // MARK: - Legacy (default group) helpers

    /// Default access group(= 팀 기본 그룹)에서 읽기. access group 지정하지 않음.
    private static func legacyLoadItem(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainSharedAccessGroup.service,
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
    private static func legacyDeleteItem(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainSharedAccessGroup.service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
