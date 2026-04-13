import Foundation
import SwiftUI
import CommonCrypto

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

    private var clientID: String = ""
    private var clientSecret: String = ""

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    private static let credentialsFileName = "google_credentials.json"

    init() {
        // Suppress SIGPIPE process-wide (socket writes to closed connections)
        signal(SIGPIPE, SIG_IGN)
        // Migrate old file-based tokens to macOS Keychain (one-time)
        KeychainHelper.migrateFromFileStorage()
        loadCredentials()
        loadTokens()
    }

    // MARK: - Credentials

    private var credentialsPath: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Planit/\(Self.credentialsFileName)")
    }

    private func loadCredentials() {
        if let data = try? Data(contentsOf: credentialsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let id = json["client_id"], let secret = json["client_secret"] {
            clientID = id
            clientSecret = secret
            return
        }
        if let bundlePath = Bundle.main.path(forResource: "google_credentials", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let id = json["client_id"], let secret = json["client_secret"] {
            clientID = id
            clientSecret = secret
            saveCredentialsToAppSupport(id: id, secret: secret)
        }
    }

    private func saveCredentialsToAppSupport(id: String, secret: String) {
        let dir = credentialsPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
        let json: [String: String] = ["client_id": id, "client_secret": secret]
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            try? data.write(to: credentialsPath, options: .atomic)
            // Set restrictive file permissions (owner read/write only)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsPath.path)
        }
    }

    func setupCredentials(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        saveCredentialsToAppSupport(id: clientID, secret: clientSecret)
    }

    var hasCredentials: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    // MARK: - Token Management

    private func loadTokens() {
        accessToken = KeychainHelper.load(key: "planit.accessToken")
        refreshToken = KeychainHelper.load(key: "planit.refreshToken")
        userEmail = KeychainHelper.load(key: "planit.userEmail")
        if let s = KeychainHelper.load(key: "planit.tokenExpiry"), let t = Double(s) {
            tokenExpiry = Date(timeIntervalSince1970: t)
        }
        isAuthenticated = refreshToken != nil
    }

    private func saveTokens() {
        if let t = accessToken { KeychainHelper.save(key: "planit.accessToken", value: t) }
        if let t = refreshToken { KeychainHelper.save(key: "planit.refreshToken", value: t) }
        if let e = tokenExpiry {
            KeychainHelper.save(key: "planit.tokenExpiry", value: "\(e.timeIntervalSince1970)")
        }
        if let email = userEmail { KeychainHelper.save(key: "planit.userEmail", value: email) }
    }

    func getValidToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        guard let rt = refreshToken else { throw AuthError.notAuthenticated }
        try await refreshAccessToken(rt)
        guard let token = accessToken else { throw AuthError.notAuthenticated }
        return token
    }

    // MARK: - PKCE

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - OAuth Flow

    func startOAuthFlow() async {
        guard hasCredentials else {
            errorMessage = "자격증명이 없습니다. google_credentials.json을 설정하세요."
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
                URLQueryItem(name: "scope", value: "openid email https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/generative-language"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
            ]

            guard let authURL = components.url else { throw AuthError.serverFailed }
            NSWorkspace.shared.open(authURL)

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
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        userEmail = nil
        isAuthenticated = false
        KeychainHelper.delete(key: "planit.accessToken")
        KeychainHelper.delete(key: "planit.refreshToken")
        KeychainHelper.delete(key: "planit.tokenExpiry")
        KeychainHelper.delete(key: "planit.userEmail")
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
                // Close serverFd after 5 minutes to unblock accept()
                let timeoutItem = DispatchWorkItem { close(serverFd) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeoutItem)

                defer {
                    timeoutItem.cancel()
                    // Only close if timeout didn't already close it
                    close(serverFd)
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

                Self.sendHTTPResponse(fd: clientFd, body: "<h1>Planit 인증 완료!</h1><p>이 창을 닫아도 됩니다.</p>")
                continuation.resume(returning: code)
            }
        }
    }

    private static func sendHTTPResponse(fd: Int32, body: String) {
        let html = "<html><body style='font-family:system-ui;text-align:center;padding:60px'>\(body)</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
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
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
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
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw AuthError.tokenExchangeFailed("Refresh HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = json["access_token"] as? String else {
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

