#if os(iOS)
import Foundation
import Security

/// iOS Keychain-backed storage for Claude API key.
///
/// - `kSecAttrService` = `calen.claude-api-key`
/// - `kSecAttrAccount` = `default` (single-user iOS app)
/// - `kSecUseDataProtectionKeychain` = `true` (iOS data-protection keychain, not legacy file-based)
/// - `kSecAttrAccessGroup` = App Group `group.com.oy.planit`
///   AUTH 팀장이 실제 팀 ID를 프리픽스로 추가 예정 (예: `ABCD1234EF.group.com.oy.planit`).
///   현재는 팀 ID 없이 그룹 suffix만 지정 — Xcode 프로젝트에서 entitlement가 설정되기 전까지는
///   access group 매칭이 실패할 수 있으므로, 실제 entitlement가 붙은 뒤 본 상수를
///   `"<TEAMID>.group.com.oy.planit"` 형식으로 갱신해야 한다.
///
/// 값 인코딩: UTF-8 `Data`. Claude API 키는 `sk-ant-...` ASCII 문자열.
public struct ClaudeAPIKeychain {

    // MARK: - Constants

    /// App Group suffix. AUTH 팀장이 실제 팀 ID 프리픽스를 추가할 예정 (`<TEAMID>.group.com.oy.planit`).
    /// 그 전까지는 suffix만으로 Keychain access group 매칭이 실패할 수 있음.
    private static let accessGroup = "group.com.oy.planit"

    private static let service = "calen.claude-api-key"
    private static let account = "default"

    // MARK: - API

    /// Claude API 키를 Keychain에 저장한다. 이미 존재하면 update, 없으면 add.
    /// 빈 문자열을 저장하면 항목을 삭제한다(call site에서의 실수 방어).
    @discardableResult
    public static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return remove()
        }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let lookup = baseQuery()
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: false
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = lookup
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrSynchronizable as String] = false
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Keychain에 저장된 Claude API 키를 로드한다. 없거나 디코딩에 실패하면 `nil`.
    public static func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Keychain에서 Claude API 키를 삭제한다. 이미 없었어도 `true`.
    @discardableResult
    public static func remove() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Private

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }
}
#endif
