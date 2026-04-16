import Foundation
import SwiftUI
import CommonCrypto
import os

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
        case .noCredentials: return "Google Cloud 자격증명이 설정되지 않았습니다"
        case .serverFailed: return "로컬 인증 서버 시작 실패"
        case .noCodeReceived: return "인증 코드를 받지 못했습니다"
        case .tokenExchangeFailed(let msg): return "토큰 교환 실패: \(msg)"
        case .notAuthenticated: return "Google 계정에 로그인되지 않았습니다"
        case .stateMismatch: return "인증 상태 불일치 (CSRF 보호)"
        case .timeout: return "인증 시간이 초과되었습니다"
        }
    }
}

@MainActor
final class GoogleAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var errorMessage: String?

    // Google Desktop OAuth credentials (non-confidential per Google's documentation).
    // Desktop app client_secrets are NOT treated as confidential by Google;
    // protection relies on PKCE + loopback redirect URI validation.
    private var clientID: String = BundledCredentials.clientID
    private var clientSecret: String = BundledCredentials.clientSecret

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var refreshTask: Task<String, Error>?

    init() {
        signal(SIGPIPE, SIG_IGN)
        KeychainHelper.migrateIfNeeded()
        loadCredentials()
        loadTokens()
    }

    // MARK: - Credentials

    private func loadCredentials() {
        // 1. Consolidated Keychain entry
        if let creds = KeychainHelper.loadCredentials() {
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
            if KeychainHelper.saveCredentials(creds) {
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
            KeychainHelper.saveCredentials(KeychainHelper.OAuthCredentials(clientID: id, clientSecret: secret))
        }
        #endif
    }

    func setupCredentials(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        KeychainHelper.saveCredentials(KeychainHelper.OAuthCredentials(clientID: clientID, clientSecret: clientSecret))
    }

    var hasCredentials: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    // MARK: - Token Management

    private func loadTokens() {
        let tokens = KeychainHelper.loadAuthTokens()
        accessToken  = tokens.accessToken
        refreshToken = tokens.refreshToken
        userEmail    = tokens.userEmail
        if let t = tokens.tokenExpiry { tokenExpiry = Date(timeIntervalSince1970: t) }
        isAuthenticated = refreshToken != nil
    }

    private func saveTokens() {
        let tokens = KeychainHelper.AuthTokens(
            accessToken:  accessToken,
            refreshToken: refreshToken,
            tokenExpiry:  tokenExpiry.map { $0.timeIntervalSince1970 },
            userEmail:    userEmail
        )
        KeychainHelper.saveAuthTokens(tokens)
    }

    func getValidToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
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

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
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
            let redirectURI = "http://localhost:\(port)"

            let state = UUID().uuidString
            let codeVerifier = Self.generateCodeVerifier()
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
        KeychainHelper.deleteAuthTokens()
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

        let (data, response) = try await URLSession.shared.data(for: request)
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
            tokenExpiry = Date().addingTimeInterval(Double(expiresIn))
        }
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

        let (data, response) = try await URLSession.shared.data(for: request)
        // 네트워크 응답 대기 중 logout()이 호출됐으면 토큰 저장을 중단
        try Task.checkCancellation()

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            // 401/403은 refresh token이 폐기/만료됨 → 자동 로그아웃
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logout()
            }
            throw AuthError.tokenExchangeFailed("Refresh HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.tokenExchangeFailed("Refresh failed")
        }
        if let error = json["error"] as? String {
            // invalid_grant도 refresh token 폐기를 의미
            if error == "invalid_grant" { logout() }
            let desc = json["error_description"] as? String ?? error
            throw AuthError.tokenExchangeFailed("Refresh: \(desc)")
        }
        guard let newToken = json["access_token"] as? String else {
            throw AuthError.tokenExchangeFailed("Refresh failed")
        }

        accessToken = newToken
        if let expiresIn = json["expires_in"] as? Int {
            tokenExpiry = Date().addingTimeInterval(Double(expiresIn))
        }
        saveTokens()
    }

    private func fetchUserEmail() async {
        guard let token = accessToken else { return }
        let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                userEmail = email
                saveTokens()
            }
        } catch {}
    }
}

