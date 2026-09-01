import Foundation
import SwiftUI
import CommonCrypto
import Combine
import os
import CalenShared

// double-close 방지용 경량 mutex
private final class UnfairLock: @unchecked Sendable {
    private let _lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    init() { _lock.initialize(to: os_unfair_lock()) }
    deinit { _lock.deallocate() }
    func lock()   { os_unfair_lock_lock(_lock) }
    func unlock() { os_unfair_lock_unlock(_lock) }
}

enum AuthError: LocalizedError {
    case noCredentials
    case serverFailed
    case noCodeReceived
    case tokenExchangeFailed(String)
    case notAuthenticated
    case stateMismatch
    case timeout

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return String(localized: "auth.error.no.credentials")
        case .serverFailed:
            return String(localized: "auth.error.server.failed")
        case .noCodeReceived:
            return String(localized: "auth.error.no.code")
        case .tokenExchangeFailed(let msg):
            // redirect_uri_mismatch → OAuth 클라이언트 타입 안내
            if msg.contains("redirect_uri_mismatch") || msg.contains("400") {
                return String(localized: "auth.error.redirect.mismatch")
            }
            return String(format: String(localized: "auth.error.token.exchange"), msg)
        case .notAuthenticated:
            return String(localized: "auth.error.not.authenticated")
        case .stateMismatch:
            return String(localized: "auth.error.state.mismatch")
        case .timeout:
            return String(localized: "auth.error.timeout")
        }
    }
}

enum GoogleAuthHealth: Equatable {
    case signedOut
    case healthy
    case retryableDegraded
    case terminalDegraded
    case revoked
}

struct GoogleAuthTokenStore {
    var loadCredentials: () -> KeychainHelper.OAuthCredentials?
    var saveCredentials: (KeychainHelper.OAuthCredentials) -> Bool
    var loadAuthTokens: () -> KeychainHelper.AuthTokens
    var saveAuthTokens: (KeychainHelper.AuthTokens) -> Bool
    var deleteAuthTokens: () -> Bool

    static let keychain = GoogleAuthTokenStore(
        loadCredentials: { KeychainHelper.loadCredentials() },
        saveCredentials: { KeychainHelper.saveCredentials($0) },
        loadAuthTokens: { KeychainHelper.loadAuthTokens() },
        saveAuthTokens: { KeychainHelper.saveAuthTokens($0) },
        deleteAuthTokens: { KeychainHelper.deleteAuthTokens() }
    )
}

@MainActor
final class GoogleAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var errorMessage: String?
    @Published private(set) var authHealth: GoogleAuthHealth = .signedOut
    /// OAuth 완료(토큰 발급)마다 발행 — isAuthenticated 변화 없어도 발행 (재연결 포함)
    let authSucceeded = PassthroughSubject<Void, Never>()

    // Google Desktop OAuth credentials (non-confidential per Google's documentation).
    // Desktop app client_secrets are NOT treated as confidential by Google;
    // protection relies on PKCE + loopback redirect URI validation.
    private var clientID: String = BundledCredentials.clientID
    private var clientSecret: String = BundledCredentials.clientSecret

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var refreshTask: Task<String, Error>?
    private let requestRunner: (URLRequest) async throws -> (Data, URLResponse)
    private let tokenStore: GoogleAuthTokenStore
    private let now: () -> Date

    init() {
        self.requestRunner = { request in try await URLSession.shared.data(for: request) }
        self.tokenStore = .keychain
        self.now = { Date() }
        signal(SIGPIPE, SIG_IGN)
        KeychainHelper.migrateIfNeeded()
        loadCredentials()
        loadTokens()
    }

    init(
        tokenStore: GoogleAuthTokenStore,
        requestRunner: @escaping (URLRequest) async throws -> (Data, URLResponse),
        now: @escaping () -> Date = { Date() },
        clientID: String = "test-client-id",
        clientSecret: String = "test-client-secret"
    ) {
        self.tokenStore = tokenStore
        self.requestRunner = requestRunner
        self.now = now
        self.clientID = clientID
        self.clientSecret = clientSecret
        loadCredentials()
        loadTokens()
    }

    var authTokenSnapshot: KeychainHelper.AuthTokens {
        KeychainHelper.AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenExpiry: tokenExpiry.map { $0.timeIntervalSince1970 },
            userEmail: userEmail
        )
    }

    // MARK: - Credentials

    private func loadCredentials() {
        // 1. Consolidated Keychain entry — 빈 값이면 무시 (삭제 후 재설치 시 stale entry 방지)
        if let creds = tokenStore.loadCredentials(),
           !creds.clientID.isEmpty, !creds.clientSecret.isEmpty {
            clientID = creds.clientID
            clientSecret = creds.clientSecret
            return
        }

        // 2. Legacy plaintext JSON file → migrate to Keychain
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let legacyPath = support.appendingPathComponent("Planit/google_credentials.json")
        if let data = try? Data(contentsOf: legacyPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let id = json["client_id"], let secret = json["client_secret"] {
            clientID = id
            clientSecret = secret
            let creds = KeychainHelper.OAuthCredentials(clientID: id, clientSecret: secret)
            if tokenStore.saveCredentials(creds) {
                try? FileManager.default.removeItem(at: legacyPath)
            }
            return
        }

        // 3. Bundle credentials (development only)
        #if DEBUG
        if let bundlePath = Bundle.main.path(forResource: "google_credentials", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let id = json["client_id"], let secret = json["client_secret"] {
            clientID = id
            clientSecret = secret
            _ = tokenStore.saveCredentials(KeychainHelper.OAuthCredentials(clientID: id, clientSecret: secret))
        }
        #endif
    }

    func setupCredentials(clientID: String, clientSecret: String) {
        // 빈 값이면 저장하지 않음 (stale Keychain entry 방지)
        guard !clientID.trimmingCharacters(in: .whitespaces).isEmpty,
              !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        self.clientID = clientID
        self.clientSecret = clientSecret
        _ = tokenStore.saveCredentials(KeychainHelper.OAuthCredentials(clientID: clientID, clientSecret: clientSecret))
    }

    var hasCredentials: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    // MARK: - Token Management

    private func loadTokens() {
        let tokens = tokenStore.loadAuthTokens()
        accessToken  = tokens.accessToken
        refreshToken = tokens.refreshToken
        userEmail    = tokens.userEmail
        if let t = tokens.tokenExpiry { tokenExpiry = Date(timeIntervalSince1970: t) }
        isAuthenticated = refreshToken != nil
        authHealth = isAuthenticated ? .healthy : .signedOut
    }

    private func saveTokens() {
        let tokens = KeychainHelper.AuthTokens(
            accessToken:  accessToken,
            refreshToken: refreshToken,
            tokenExpiry:  tokenExpiry.map { $0.timeIntervalSince1970 },
            userEmail:    userEmail
        )
        _ = tokenStore.saveAuthTokens(tokens)
    }

    func getValidToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > now().addingTimeInterval(60) {
            return token
        }
        if let existing = refreshTask {
            return try await existing.value
        }
        let task = Task<String, Error> { [weak self] in
            defer { Task { @MainActor in self?.refreshTask = nil } }
            guard let self, let rt = self.refreshToken else { throw AuthError.notAuthenticated }
            try await self.refreshAccessToken(rt)
            guard let token = self.accessToken else { throw AuthError.notAuthenticated }
            return token
        }
        refreshTask = task
        return try await task.value
    }

    // MARK: - PKCE

    private static func generateCodeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AuthError.serverFailed
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - OAuth Flow

    func startOAuthFlow() async {
        guard hasCredentials else {
            errorMessage = "자격증명이 없습니다. 설정에서 Google OAuth 클라이언트를 등록하세요."
            return
        }
        errorMessage = nil

        var serverFd: Int32 = -1
        do {
            serverFd = try createLoopbackSocket()
            let port = try getSocketPort(serverFd)
            let redirectURI = "http://127.0.0.1:\(port)"

            let state = UUID().uuidString
            let codeVerifier = try Self.generateCodeVerifier()
            let codeChallenge = Self.generateCodeChallenge(from: codeVerifier)

            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/userinfo.email"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
            ]

            guard let authURL = components.url else { throw AuthError.serverFailed }
            openURL(authURL)

            let code = try await waitForAuthCode(serverFd: serverFd, expectedState: state)
            // serverFd is closed inside waitForAuthCode
            serverFd = -1
            try await exchangeCodeForTokens(code: code, redirectURI: redirectURI, codeVerifier: codeVerifier)
            await fetchUserEmail()
            isAuthenticated = true
            authSucceeded.send()
        } catch {
            if serverFd >= 0 { close(serverFd) }
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        // 진행 중인 토큰 갱신 취소 — 갱신 완료 후 토큰이 재저장되는 것을 방지
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        userEmail = nil
        isAuthenticated = false
        authHealth = .signedOut
        errorMessage = nil
        _ = tokenStore.deleteAuthTokens()
    }

    // MARK: - Loopback Server

    private func createLoopbackSocket() throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AuthError.serverFailed }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        // Suppress SIGPIPE on this socket
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { close(fd); throw AuthError.serverFailed }
        guard listen(fd, 1) == 0 else { close(fd); throw AuthError.serverFailed }

        return fd
    }

    private func getSocketPort(_ fd: Int32) throws -> UInt16 {
        var addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        return UInt16(bigEndian: addr.sin_port)
    }

    private func waitForAuthCode(serverFd: Int32, expectedState: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // atomic flag — 타임아웃과 defer 중 딱 한 번만 close()
                let closed = UnfairLock()
                var didClose = false
                let safeClose = {
                    closed.lock()
                    defer { closed.unlock() }
                    guard !didClose else { return }
                    didClose = true
                    close(serverFd)
                }

                // 90초 타임아웃으로 단축 (5분 → 90초)
                let timeoutItem = DispatchWorkItem { safeClose() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: timeoutItem)

                defer {
                    timeoutItem.cancel()
                    safeClose()
                }

                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(serverFd, $0, &clientLen)
                    }
                }
                guard clientFd >= 0 else {
                    continuation.resume(throwing: AuthError.serverFailed)
                    return
                }
                defer { close(clientFd) }

                // Set read timeout on client socket
                var clientTimeout = timeval(tv_sec: 10, tv_usec: 0)
                setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &clientTimeout, socklen_t(MemoryLayout.size(ofValue: clientTimeout)))
                // Suppress SIGPIPE on client socket
                var yes: Int32 = 1
                setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

                var buffer = [UInt8](repeating: 0, count: 8192)
                let n = read(clientFd, &buffer, buffer.count)
                guard n > 0 else {
                    continuation.resume(throwing: AuthError.noCodeReceived)
                    return
                }

                let request = String(bytes: buffer[0..<n], encoding: .utf8) ?? ""
                let parts = request.split(separator: " ")
                guard parts.count >= 2,
                      let comps = URLComponents(string: String(parts[1])),
                      let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
                    Self.sendHTTPResponse(fd: clientFd, body: "<h2>인증 실패</h2><p>다시 시도해주세요.</p>")
                    continuation.resume(throwing: AuthError.noCodeReceived)
                    return
                }

                guard let receivedState = comps.queryItems?.first(where: { $0.name == "state" })?.value,
                      receivedState == expectedState else {
                    Self.sendHTTPResponse(fd: clientFd, body: "<h2>인증 실패</h2><p>상태 불일치</p>")
                    continuation.resume(throwing: AuthError.stateMismatch)
                    return
                }

                Self.sendHTTPResponse(fd: clientFd, body: "<h1>Calen 인증 완료!</h1><p>이 창을 닫아도 됩니다.</p>")
                continuation.resume(returning: code)
            }
        }
    }

    nonisolated private static func sendHTTPResponse(fd: Int32, body: String) {
        let html = "<html><body style='font-family:system-ui;text-align:center;padding:60px'>\(body)</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\n\r\n\(html)"
        let bytes = Array(response.utf8)
        var totalWritten = 0
        while totalWritten < bytes.count {
            let written = bytes.withUnsafeBufferPointer { buf in
                Darwin.send(fd, buf.baseAddress!.advanced(by: totalWritten), bytes.count - totalWritten, 0)
            }
            if written < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                break
            }
            if written == 0 { break }
            totalWritten += written
        }
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, redirectURI: String, codeVerifier: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [(String, String)] = [
            ("code", code),
            ("client_id", clientID),
            ("client_secret", clientSecret),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", codeVerifier),
        ]
        let body = params.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await requestRunner(request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw AuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.tokenExchangeFailed("Invalid response")
        }

        if let error = json["error"] as? String {
            let desc = json["error_description"] as? String ?? error
            throw AuthError.tokenExchangeFailed(desc)
        }

        accessToken = json["access_token"] as? String
        refreshToken = json["refresh_token"] as? String ?? refreshToken
        if let expiresIn = json["expires_in"] as? Int {
            tokenExpiry = now().addingTimeInterval(Double(expiresIn))
        }
        authHealth = .healthy
        errorMessage = nil
        saveTokens()
    }

    private func refreshAccessToken(_ refreshToken: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [(String, String)] = [
            ("client_id", clientID),
            ("client_secret", clientSecret),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
        ]
        let body = params.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await requestRunner(request)
        } catch {
            try Task.checkCancellation()
            markRefreshFailure(.retryableTransient)
            throw AuthError.tokenExchangeFailed("Refresh: retryableTransient")
        }
        // 네트워크 응답 대기 중 logout()이 호출됐으면 토큰 저장을 중단
        try Task.checkCancellation()

        let statusCode = (response as? HTTPURLResponse)?.statusCode
        let classification = OAuthRefreshErrorClassifier.classify(statusCode: statusCode, body: data)
        guard classification == .success else {
            markRefreshFailure(classification)
            throw AuthError.tokenExchangeFailed("Refresh: \(classification)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            markRefreshFailure(.retryableTransient)
            throw AuthError.tokenExchangeFailed("Refresh failed")
        }

        guard let newToken = json["access_token"] as? String else {
            markRefreshFailure(.retryableTransient)
            throw AuthError.tokenExchangeFailed("Refresh failed")
        }

        accessToken = newToken
        if let expiresIn = json["expires_in"] as? Int {
            tokenExpiry = now().addingTimeInterval(Double(expiresIn))
        }
        authHealth = .healthy
        errorMessage = nil
        saveTokens()
    }

    private func markRefreshFailure(_ classification: OAuthRefreshClassification) {
        switch classification {
        case .success:
            authHealth = .healthy
            errorMessage = nil
        case .permanentRevocation:
            logout()
            authHealth = .revoked
            errorMessage = String(localized: "auth.refresh.permanent_revocation", bundle: .module)
        case .nonRevocationTerminal:
            authHealth = .terminalDegraded
            errorMessage = String(localized: "auth.refresh.non_revocation_terminal", bundle: .module)
        case .retryableTransient:
            authHealth = .retryableDegraded
            errorMessage = String(localized: "auth.refresh.retryable_transient", bundle: .module)
        }
    }

    private func fetchUserEmail() async {
        guard let token = accessToken else { return }
        let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await requestRunner(request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                userEmail = email
                saveTokens()
            }
        } catch {}
    }
}
