// Google OAuth credentials.
// 실제 값은 BundledCredentials.local.swift (gitignore)에 정의.
// CI 빌드 시 GitHub Secret으로 BundledCredentials.local.swift 자동 생성.
enum BundledCredentials {
    #if HAS_BUNDLED_CREDENTIALS
    static let clientID: String = _localClientID
    static let clientSecret: String = _localClientSecret
    #else
    static let clientID: String = ""
    static let clientSecret: String = ""
    #endif
}
