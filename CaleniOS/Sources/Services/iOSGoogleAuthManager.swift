#if os(iOS)
import Foundation
import SwiftUI
import AuthenticationServices
import CommonCrypto
import CalenShared

// MARK: - iOS Google OAuth Manager
//
// macOS는 loopback 127.0.0.1 + `NSWorkspace.open` 로 OAuth 를 돌린다.
// 그 경로는 iOS에서 둘 다 불가하므로(loopback → Google이 iOS에서 deprecated,
// AppKit 부재), iOS는 **ASWebAuthenticationSession** + **reversed-client-ID URL scheme**
// 으로 다시 구현한다.
//
// 공유되는 것:
//  - 프로토콜 `CalendarAuthProviding` (Shared)
//  - Keychain (App Group `group.com.oy.planit` via `SharedKeychainHelper`)
//  - Codable 구조체 (`KeychainHelper.AuthTokens`, `.OAuthCredentials`) — iOS target에 없으므로
//    동일 구조체를 여기서 shadow해서 사용한다. SharedKeychainHelper가 macOS 타깃에만
//    있는 것을 iOS에서 복제: 아래 `LocalKeychain` 사용.

// MARK: - iOS 전용 Keychain (App Group 공유)
//
// macOS의 `SharedKeychainHelper`와 동일 스키마를 iOS에서도 쓸 수 있도록 복제한다.
// (SharedKeychainHelper는 `Calen` 타깃에 속해서 iOS 타깃에서는 import 불가.)
enum IOSSharedKeychain {
    /// App Group id — RELEASE 팀장이 Team ID prefix 가 필요하면 주입.
    static let accessGroup: String = "group.com.oy.planit"
    static let service: String = "com.oy.planit"
    static let tokenAccount: String = "planit.auth.tokens"
    static let credentialsAccount: String = "planit.auth.credentials"

    struct AuthTokens: Codable, Equatable {
        var accessToken: String?
        var refreshToken: String?
        var tokenExpiry: Double?
        var userEmail: String?
    }

    struct OAuthCredentials: Codable, Equatable {
        var clientID: String
        var clientSecret: String
    }

    // MARK: CRUD

    @discardableResult
    static func saveItem(account: String, data: Data) -> Bool {
        var lookup = baseQuery(account: account)
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(lookup as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        lookup[kSecValueData as String] = data
        lookup[kSecAttrSynchronizable as String] = false
        lookup[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(lookup as CFDictionary, nil) == errSecSuccess
    }

    static func loadItem(account: String) -> Data? {
        var q = baseQuery(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return data
    }

    @discardableResult
    static func deleteItem(account: String) -> Bool {
        let q = baseQuery(account: account)
        let s = SecItemDelete(q as CFDictionary)
        return s == errSecSuccess || s == errSecItemNotFound
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    // MARK: Typed helpers

    static func loadTokens() -> AuthTokens {
        guard let data = loadItem(account: tokenAccount),
              let t = try? JSONDecoder().decode(AuthTokens.self, from: data) else {
            return AuthTokens()
        }
        return t
    }

    @discardableResult
    static func saveTokens(_ t: AuthTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(t) else { return false }
        return saveItem(account: tokenAccount, data: data)
    }

    @discardableResult
    static func deleteTokens() -> Bool { deleteItem(account: tokenAccount) }

    static func loadCredentials() -> OAuthCredentials? {
        guard let data = loadItem(account: credentialsAccount) else { return nil }
        return try? JSONDecoder().decode(OAuthCredentials.self, from: data)
    }

    @discardableResult
    static func saveCredentials(_ c: OAuthCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(c) else { return false }
        return saveItem(account: credentialsAccount, data: data)
    }
}

// MARK: - Errors

public enum IOSAuthError: LocalizedError, Equatable {
    case credentialsMissing
    case userCancelled
    case invalidCallback
    case stateMismatch
    case tokenExchangeFailed(String)
    case notAuthenticated
    case noPresentationAnchor

    public var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            return "Google OAuth 클라이언트 ID가 없습니다. 설정에서 입력하세요."
        case .userCancelled:
            return "로그인이 취소되었습니다."
        case .invalidCallback:
            return "OAuth 콜백이 올바르지 않습니다."
        case .stateMismatch:
            return "state 값이 일치하지 않습니다. 다시 시도해주세요."
        case .tokenExchangeFailed(let msg):
            return "토큰 교환 실패: \(msg)"
        case .notAuthenticated:
            return "로그인이 필요합니다."
        case .noPresentationAnchor:
            return "로그인 창을 띄울 위치를 찾지 못했습니다."
        }
    }
}

// MARK: - iOSGoogleAuthManager

@MainActor
public final class iOSGoogleAuthManager: NSObject, ObservableObject, CalendarAuthProviding {
    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var userEmail: String?
    @Published public var errorMessage: String?

    // Google OAuth 클라이언트 ID (reversed-client-ID URL scheme 기반).
    // iOS는 client_secret을 사용하지 않는다 (installed app w/ PKCE + custom scheme).
    private var clientID: String = ""
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var refreshTask: Task<String, Error>?

    // 진행 중 ASWebAuthenticationSession (강한 참조 유지 필요)
    private var webAuthSession: ASWebAuthenticationSession?

    // MARK: Scope — 초기에는 macOS와 동일 범위
    private let scopes = ["https://www.googleapis.com/auth/calendar"]

    public override init() {
        super.init()
        _ = SharedKeychainMigrationIfNeeded()
        loadCredentials()
        loadTokens()
    }

    // MARK: - Credentials

    /// Bundled client ID 로딩. iOS 타깃은 `BundledCredentials`가 컴파일되어 있지 않을 수도 있으므로
    /// Info.plist → UserDefaults → Keychain 순으로 fallback.
    private func loadCredentials() {
        // 1. Keychain(App Group) 에 저장된 값이 우선
        if let c = IOSSharedKeychain.loadCredentials(), !c.clientID.isEmpty {
            self.clientID = c.clientID
            return
        }
        // 2. Info.plist 의 `GoogleClientID` 키 (RELEASE 팀장이 실제 값 주입)
        if let s = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String,
           !s.isEmpty {
            self.clientID = s
            return
        }
        // 3. 그 외에는 비어있음 — `setupCredentials` 호출 필요
    }

    /// 사용자가 직접 client ID를 입력하는 경로 (설정 화면).
    public func setupCredentials(clientID: String) {
        let trimmed = clientID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        self.clientID = trimmed
        IOSSharedKeychain.saveCredentials(
            IOSSharedKeychain.OAuthCredentials(clientID: trimmed, clientSecret: "")
        )
    }

    public var hasCredentials: Bool { !clientID.isEmpty }

    /// `com.googleusercontent.apps.<CLIENT_ID_PREFIX>` 형태의 reversed-client-ID.
    /// e.g. client_id "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    var reversedClientIDScheme: String? {
        guard !clientID.isEmpty else { return nil }
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let prefix = String(clientID.dropLast(suffix.count))
        return "com.googleusercontent.apps.\(prefix)"
    }

    /// redirect URI — Google iOS OAuth 권장: `<reversed>:/oauth2redirect`
    var redirectURI: String? {
        guard let scheme = reversedClientIDScheme else { return nil }
        return "\(scheme):/oauth2redirect"
    }

    // MARK: - Token management

    private func loadTokens() {
        let t = IOSSharedKeychain.loadTokens()
        self.accessToken = t.accessToken
        self.refreshToken = t.refreshToken
        self.userEmail = t.userEmail
        if let exp = t.tokenExpiry { self.tokenExpiry = Date(timeIntervalSince1970: exp) }
        self.isAuthenticated = (t.refreshToken != nil)
    }

    private func saveTokens() {
        let t = IOSSharedKeychain.AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenExpiry: tokenExpiry.map { $0.timeIntervalSince1970 },
            userEmail: userEmail
        )
        IOSSharedKeychain.saveTokens(t)
    }

    // MARK: CalendarAuthProviding

    public var currentAccessToken: String? {
        get async { try? await getValidToken() }
    }

    public func refreshIfNeeded() async throws {
        _ = try await getValidToken()
    }

    public func getValidToken() async throws -> String {
        if let token = accessToken, let exp = tokenExpiry, exp > Date().addingTimeInterval(60) {
            return token
        }
        if let existing = refreshTask {
            return try await existing.value
        }
        let task = Task<String, Error> { [weak self] in
            defer { Task { @MainActor in self?.refreshTask = nil } }
            guard let self else { throw IOSAuthError.notAuthenticated }
            guard let rt = await self.refreshToken else { throw IOSAuthError.notAuthenticated }
            try await self.performRefresh(refreshToken: rt)
            guard let token = await self.accessToken else { throw IOSAuthError.notAuthenticated }
            return token
        }
        refreshTask = task
        return try await task.value
    }

    // MARK: - OAuth flow

    /// ASWebAuthenticationSession을 띄우고, 콜백 URL에서 code를 회수한 후 토큰 교환까지 처리.
    public func startOAuthFlow() async {
        guard hasCredentials else {
            errorMessage = IOSAuthError.credentialsMissing.errorDescription
            return
        }
        guard let scheme = reversedClientIDScheme, let redirect = redirectURI else {
            errorMessage = IOSAuthError.credentialsMissing.errorDescription
            return
        }
        errorMessage = nil

        do {
            let state = UUID().uuidString
            let verifier = try Self.generateCodeVerifier()
            let challenge = Self.generateCodeChallenge(from: verifier)

            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirect),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
            ]
            guard let authURL = components.url else {
                throw IOSAuthError.tokenExchangeFailed("bad auth URL")
            }

            let callbackURL = try await runWebAuth(url: authURL, callbackScheme: scheme)
            let (code, receivedState) = try parseCallback(callbackURL)
            guard receivedState == state else { throw IOSAuthError.stateMismatch }

            try await exchangeCodeForTokens(code: code, redirect: redirect, verifier: verifier)
            await fetchUserEmail()
            isAuthenticated = true
        } catch let err as IOSAuthError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func logout() {
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        userEmail = nil
        isAuthenticated = false
        IOSSharedKeychain.deleteTokens()
    }

    // MARK: - ASWebAuthenticationSession

    private func runWebAuth(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callback, error in
                if let error = error as? ASWebAuthenticationSessionError {
                    switch error.code {
                    case .canceledLogin:
                        cont.resume(throwing: IOSAuthError.userCancelled)
                    default:
                        cont.resume(throwing: IOSAuthError.tokenExchangeFailed(error.localizedDescription))
                    }
                    return
                }
                if let error = error {
                    cont.resume(throwing: IOSAuthError.tokenExchangeFailed(error.localizedDescription))
                    return
                }
                guard let cb = callback else {
                    cont.resume(throwing: IOSAuthError.invalidCallback)
                    return
                }
                cont.resume(returning: cb)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            self.webAuthSession = session
            if !session.start() {
                self.webAuthSession = nil
                cont.resume(throwing: IOSAuthError.noPresentationAnchor)
            }
        }
    }

    private func parseCallback(_ url: URL) throws -> (code: String, state: String) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw IOSAuthError.invalidCallback
        }
        guard let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = comps.queryItems?.first(where: { $0.name == "state" })?.value else {
            if let err = comps.queryItems?.first(where: { $0.name == "error" })?.value {
                throw IOSAuthError.tokenExchangeFailed(err)
            }
            throw IOSAuthError.invalidCallback
        }
        return (code, state)
    }

    // MARK: - Token exchange / refresh

    private func exchangeCodeForTokens(code: String, redirect: String, verifier: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // installed-app (iOS) 플로우는 client_secret이 선택적 — 전달하지 않는다 (PKCE로 대체).
        let params: [(String, String)] = [
            ("code", code),
            ("client_id", clientID),
            ("redirect_uri", redirect),
            ("grant_type", "authorization_code"),
            ("code_verifier", verifier),
        ]
        req.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw IOSAuthError.tokenExchangeFailed("HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IOSAuthError.tokenExchangeFailed("invalid response")
        }
        if let err = json["error"] as? String {
            let desc = (json["error_description"] as? String) ?? err
            throw IOSAuthError.tokenExchangeFailed(desc)
        }
        self.accessToken = json["access_token"] as? String
        // refresh_token 은 최초 로그인에만 내려옴 — 없으면 기존 값 유지
        self.refreshToken = (json["refresh_token"] as? String) ?? self.refreshToken
        if let exp = json["expires_in"] as? Int {
            self.tokenExpiry = Date().addingTimeInterval(TimeInterval(exp))
        }
        saveTokens()
    }

    private func performRefresh(refreshToken: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [(String, String)] = [
            ("client_id", clientID),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
        ]
        req.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Task.checkCancellation()

        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 401 || http.statusCode == 403 {
                logout()
            }
            throw IOSAuthError.tokenExchangeFailed("refresh HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IOSAuthError.tokenExchangeFailed("refresh: bad JSON")
        }
        if let err = json["error"] as? String {
            if err == "invalid_grant" { logout() }
            let desc = (json["error_description"] as? String) ?? err
            throw IOSAuthError.tokenExchangeFailed("refresh: \(desc)")
        }
        guard let newToken = json["access_token"] as? String else {
            throw IOSAuthError.tokenExchangeFailed("refresh: no access_token")
        }
        self.accessToken = newToken
        if let exp = json["expires_in"] as? Int {
            self.tokenExpiry = Date().addingTimeInterval(TimeInterval(exp))
        }
        saveTokens()
    }

    private func fetchUserEmail() async {
        guard let token = accessToken else { return }
        let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                self.userEmail = email
                saveTokens()
            }
        } catch {
            // best-effort: 이메일 없이도 인증은 유효
        }
    }

    // MARK: - PKCE helpers

    static func generateCodeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw IOSAuthError.tokenExchangeFailed("RNG failed")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func formEncode(_ params: [(String, String)]) -> String {
        params.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension iOSGoogleAuthManager: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Active foreground scene의 key window를 찾는다. 없으면 빈 anchor.
        // `@MainActor`로 UIApplication API 접근이 필요하지만 nonisolated 요구사항이므로 동기 hop.
        // iOS 15+ 보장: UIApplication.shared는 MainActor-isolated 이지만, 이 시점은 UI가
        // 활성화된 상태이므로 runtime에서 실제 호출 위치는 main thread.
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
            if let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
                return window
            }
            if let any = scenes.flatMap({ $0.windows }).first {
                return any
            }
            return UIWindow()
        }
    }
}

// MARK: - One-shot migration shim
//
// 이 파일은 `Calen` 타깃 소유인 `SharedKeychainHelper.migrateToSharedGroup()`에 접근할 수 없다.
// iOS 타깃은 default keychain access group → shared 이동이 필요 없지만 (fresh install),
// 사용자가 향후 구판 → 신판 업그레이드할 때를 대비해 iOS 자체에서도 동일 migration 훅을 둔다.
private func SharedKeychainMigrationIfNeeded() -> Bool {
    let defaults = UserDefaults.standard
    let key = "planit.ios.keychain.sharedGroup.migrationDone.v1"
    if defaults.bool(forKey: key) { return true }

    // Legacy(= access group 없이 저장된) 토큰이 있으면 shared group으로 복사.
    func legacyLoad(account: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: IOSSharedKeychain.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return data
    }
    func legacyDelete(account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: IOSSharedKeychain.service,
            kSecAttrAccount as String: account,
        ]
        _ = SecItemDelete(q as CFDictionary)
    }

    var ok = true
    for account in [IOSSharedKeychain.tokenAccount, IOSSharedKeychain.credentialsAccount] {
        if let data = legacyLoad(account: account) {
            if IOSSharedKeychain.saveItem(account: account, data: data) {
                legacyDelete(account: account)
            } else {
                ok = false
            }
        }
    }
    if ok { defaults.set(true, forKey: key) }
    return ok
}
#endif
