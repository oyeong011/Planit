import Foundation
import Testing
@testable import Calen

@MainActor
struct GoogleAuthManagerRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("refresh success persists new access token and expiry")
    func refreshSuccessPersistsNewAccessTokenAndExpiry() async throws {
        let initialTokens = expiredTokens()
        let store = InMemoryAuthTokenStore(tokens: initialTokens)
        let manager = makeManager(
            store: store,
            response: httpResponse(
                statusCode: 200,
                body: #"{"access_token":"new-access","expires_in":3600}"#
            )
        )

        let token = try await manager.getValidToken()

        #expect(token == "new-access")
        #expect(manager.authHealth == .healthy)
        #expect(manager.errorMessage == nil)
        #expect(manager.isAuthenticated)
        assertTokens(
            manager.authTokenSnapshot,
            accessToken: "new-access",
            refreshToken: initialTokens.refreshToken,
            expiry: now.addingTimeInterval(3600).timeIntervalSince1970,
            userEmail: initialTokens.userEmail
        )
        assertTokens(
            store.tokens,
            accessToken: "new-access",
            refreshToken: initialTokens.refreshToken,
            expiry: now.addingTimeInterval(3600).timeIntervalSince1970,
            userEmail: initialTokens.userEmail
        )
        #expect(store.saveCount == 1)
        #expect(store.deleteCount == 0)
    }

    @Test("concurrent getValidToken calls share one refresh request")
    func concurrentGetValidTokenCallsShareOneRefreshRequest() async throws {
        let initialTokens = expiredTokens()
        let store = InMemoryAuthTokenStore(tokens: initialTokens)
        let runner = BlockingRefreshRunner()
        let manager = GoogleAuthManager(
            tokenStore: store.asTokenStore(),
            requestRunner: { request in
                #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
                return await runner.run(request)
            },
            now: { now }
        )

        let first = Task { @MainActor in try await manager.getValidToken() }
        await runner.waitUntilCallCount(1)

        let second = Task { @MainActor in try await manager.getValidToken() }
        await Task.yield()
        #expect(runner.currentCallCount() == 1)

        runner.complete(
            with: httpResponse(
                statusCode: 200,
                body: #"{"access_token":"shared-access","expires_in":3600}"#
            )
        )

        let firstToken = try await first.value
        let secondToken = try await second.value

        #expect(firstToken == "shared-access")
        #expect(secondToken == "shared-access")
        #expect(runner.currentCallCount() == 1)
        #expect(store.saveCount == 1)
        #expect(store.deleteCount == 0)
        assertTokens(
            manager.authTokenSnapshot,
            accessToken: "shared-access",
            refreshToken: initialTokens.refreshToken,
            expiry: now.addingTimeInterval(3600).timeIntervalSince1970,
            userEmail: initialTokens.userEmail
        )
        assertTokens(store.tokens, expected: manager.authTokenSnapshot)
    }

    @Test("logout during in-flight refresh prevents post-logout token re-save")
    func logoutDuringInFlightRefreshPreventsPostLogoutTokenResave() async {
        let store = InMemoryAuthTokenStore(tokens: expiredTokens())
        let runner = BlockingRefreshRunner()
        let manager = GoogleAuthManager(
            tokenStore: store.asTokenStore(),
            requestRunner: { request in
                #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
                return await runner.run(request)
            },
            now: { now }
        )

        let refresh = Task { @MainActor in try await manager.getValidToken() }
        await runner.waitUntilCallCount(1)

        manager.logout()
        assertTokens(manager.authTokenSnapshot, accessToken: nil, refreshToken: nil, expiry: nil, userEmail: nil)
        assertTokens(store.tokens, accessToken: nil, refreshToken: nil, expiry: nil, userEmail: nil)
        #expect(!manager.isAuthenticated)
        #expect(manager.authHealth == .signedOut)
        #expect(store.saveCount == 0)
        #expect(store.deleteCount == 1)

        runner.complete(
            with: httpResponse(
                statusCode: 200,
                body: #"{"access_token":"resurrected-access","expires_in":3600}"#
            )
        )

        do {
            _ = try await refresh.value
            Issue.record("Expected cancelled in-flight refresh not to return a token")
        } catch {}

        assertTokens(manager.authTokenSnapshot, accessToken: nil, refreshToken: nil, expiry: nil, userEmail: nil)
        assertTokens(store.tokens, accessToken: nil, refreshToken: nil, expiry: nil, userEmail: nil)
        #expect(!manager.isAuthenticated)
        #expect(manager.authHealth == .signedOut)
        #expect(store.saveCount == 0)
        #expect(store.deleteCount == 1)
    }

    @Test("permanent revocation clears memory and token store")
    func permanentRevocationClearsMemoryAndTokenStore() async {
        let store = InMemoryAuthTokenStore(tokens: expiredTokens())
        let manager = makeManager(
            store: store,
            response: httpResponse(statusCode: 400, body: #"{"error":"invalid_grant"}"#)
        )

        await expectRefreshFailure(manager)

        #expect(manager.authHealth == .revoked)
        #expect(manager.errorMessage == localized("auth.refresh.permanent_revocation"))
        #expect(!manager.isAuthenticated)
        assertTokens(manager.authTokenSnapshot, accessToken: nil, refreshToken: nil, expiry: nil, userEmail: nil)
        assertTokens(store.tokens, accessToken: nil, refreshToken: nil, expiry: nil, userEmail: nil)
        #expect(store.saveCount == 0)
        #expect(store.deleteCount == 1)
    }

    @Test("non-revocation terminal refresh errors preserve auth material")
    func nonRevocationTerminalPreservesAuthMaterial() async {
        let initialTokens = expiredTokens()
        let store = InMemoryAuthTokenStore(tokens: initialTokens)
        let manager = makeManager(
            store: store,
            response: httpResponse(statusCode: 400, body: #"{"error":"invalid_client"}"#)
        )

        await expectRefreshFailure(manager)

        assertPreservedAuthMaterial(
            manager: manager,
            store: store,
            expectedTokens: initialTokens,
            expectedHealth: .terminalDegraded,
            expectedError: localized("auth.refresh.non_revocation_terminal")
        )
    }

    @Test("retryable transient refresh errors preserve auth material")
    func retryableTransientPreservesAuthMaterial() async {
        let cases: [(String, StubResult)] = [
            ("http-401-empty", .response(httpResponse(statusCode: 401, body: ""))),
            ("http-403-empty", .response(httpResponse(statusCode: 403, body: ""))),
            ("http-500", .response(httpResponse(statusCode: 500, body: "temporarily unavailable"))),
            ("malformed-json", .response(httpResponse(statusCode: 200, body: #"{"access_token":"#))),
            ("missing-token", .response(httpResponse(statusCode: 200, body: #"{"expires_in":3600}"#))),
            ("network-error", .throwing(URLError(.timedOut)))
        ]

        for (name, result) in cases {
            let initialTokens = expiredTokens()
            let store = InMemoryAuthTokenStore(tokens: initialTokens)
            let manager = makeManager(store: store, result: result)

            await expectRefreshFailure(manager, sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column))

            assertPreservedAuthMaterial(
                manager: manager,
                store: store,
                expectedTokens: initialTokens,
                expectedHealth: .retryableDegraded,
                expectedError: localized("auth.refresh.retryable_transient"),
                comment: Comment(rawValue: name)
            )
        }
    }

    @Test("transient 403 HTML keeps store and marks retryable degraded")
    func transient403HTMLLeavesStoreDeleteCountAtZero() async {
        let initialTokens = expiredTokens()
        let store = InMemoryAuthTokenStore(tokens: initialTokens)
        let manager = makeManager(
            store: store,
            response: httpResponse(statusCode: 403, body: "<html>forbidden</html>")
        )

        await expectRefreshFailure(manager)

        assertPreservedAuthMaterial(
            manager: manager,
            store: store,
            expectedTokens: initialTokens,
            expectedHealth: .retryableDegraded,
            expectedError: localized("auth.refresh.retryable_transient")
        )
        #expect(store.deleteCount == 0)
    }

    @Test("adapter currentAccessToken exposes degraded health without login collapse")
    func adapterCurrentAccessTokenExposesDegradedHealthWithoutLoginCollapse() async {
        let initialTokens = expiredTokens()
        let store = InMemoryAuthTokenStore(tokens: initialTokens)
        let manager = makeManager(
            store: store,
            response: httpResponse(statusCode: 500, body: "temporarily unavailable")
        )

        let token = await manager.currentAccessToken

        #expect(token == nil)
        assertPreservedAuthMaterial(
            manager: manager,
            store: store,
            expectedTokens: initialTokens,
            expectedHealth: .retryableDegraded,
            expectedError: localized("auth.refresh.retryable_transient")
        )
    }

    private func makeManager(
        store: InMemoryAuthTokenStore,
        response: (Data, URLResponse)
    ) -> GoogleAuthManager {
        makeManager(store: store, result: .response(response))
    }

    private func makeManager(
        store: InMemoryAuthTokenStore,
        result: StubResult
    ) -> GoogleAuthManager {
        GoogleAuthManager(
            tokenStore: store.asTokenStore(),
            requestRunner: { request in
                #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
                switch result {
                case .response(let response):
                    return response
                case .throwing(let error):
                    throw error
                }
            },
            now: { now }
        )
    }

    private func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module)
    }

    private func expiredTokens() -> KeychainHelper.AuthTokens {
        KeychainHelper.AuthTokens(
            accessToken: "old-access",
            refreshToken: "refresh-token",
            tokenExpiry: now.addingTimeInterval(-120).timeIntervalSince1970,
            userEmail: "person@example.com"
        )
    }

    private func httpResponse(statusCode: Int, body: String) -> (Data, URLResponse) {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }

    private func expectRefreshFailure(
        _ manager: GoogleAuthManager,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        do {
            _ = try await manager.getValidToken()
            Issue.record("Expected refresh to fail", sourceLocation: sourceLocation)
        } catch {}
    }

    private func assertPreservedAuthMaterial(
        manager: GoogleAuthManager,
        store: InMemoryAuthTokenStore,
        expectedTokens: KeychainHelper.AuthTokens,
        expectedHealth: GoogleAuthHealth,
        expectedError: String,
        comment: Comment? = nil
    ) {
        #expect(manager.authHealth == expectedHealth, comment)
        #expect(manager.errorMessage == expectedError, comment)
        #expect(manager.isAuthenticated, comment)
        assertTokens(manager.authTokenSnapshot, expected: expectedTokens, comment: comment)
        assertTokens(store.tokens, expected: expectedTokens, comment: comment)
        #expect(store.saveCount == 0, comment)
        #expect(store.deleteCount == 0, comment)
    }

    private func assertTokens(
        _ actual: KeychainHelper.AuthTokens,
        expected: KeychainHelper.AuthTokens,
        comment: Comment? = nil
    ) {
        assertTokens(
            actual,
            accessToken: expected.accessToken,
            refreshToken: expected.refreshToken,
            expiry: expected.tokenExpiry,
            userEmail: expected.userEmail,
            comment: comment
        )
    }

    private func assertTokens(
        _ actual: KeychainHelper.AuthTokens,
        accessToken: String?,
        refreshToken: String?,
        expiry: Double?,
        userEmail: String?,
        comment: Comment? = nil
    ) {
        #expect(actual.accessToken == accessToken, comment)
        #expect(actual.refreshToken == refreshToken, comment)
        #expect(actual.tokenExpiry == expiry, comment)
        #expect(actual.userEmail == userEmail, comment)
    }
}

private enum StubResult {
    case response((Data, URLResponse))
    case throwing(Error)
}

@MainActor
private final class BlockingRefreshRunner {
    private var callCount = 0
    private var callCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var response: (Data, URLResponse)?
    private var responseWaiters: [CheckedContinuation<(Data, URLResponse), Never>] = []

    func run(_ request: URLRequest) async -> (Data, URLResponse) {
        callCount += 1
        let readyWaiters = callCountWaiters
            .filter { callCount >= $0.0 }
            .map(\.1)
        callCountWaiters.removeAll { callCount >= $0.0 }

        for waiter in readyWaiters {
            waiter.resume()
        }

        if let response {
            return response
        }

        return await withCheckedContinuation { continuation in
            if let responseToResume = response {
                continuation.resume(returning: responseToResume)
            } else {
                responseWaiters.append(continuation)
            }
        }
    }

    func waitUntilCallCount(_ expectedCallCount: Int) async {
        if callCount >= expectedCallCount {
            return
        }

        await withCheckedContinuation { continuation in
            if callCount >= expectedCallCount {
                continuation.resume()
            } else {
                callCountWaiters.append((expectedCallCount, continuation))
            }
        }
    }

    func complete(with response: (Data, URLResponse)) {
        self.response = response
        let waiters = responseWaiters
        responseWaiters.removeAll()

        for waiter in waiters {
            waiter.resume(returning: response)
        }
    }

    func currentCallCount() -> Int {
        return callCount
    }
}

private final class InMemoryAuthTokenStore {
    var tokens: KeychainHelper.AuthTokens
    var saveCount = 0
    var deleteCount = 0

    init(tokens: KeychainHelper.AuthTokens) {
        self.tokens = tokens
    }

    func asTokenStore() -> GoogleAuthTokenStore {
        GoogleAuthTokenStore(
            loadCredentials: {
                KeychainHelper.OAuthCredentials(clientID: "test-client-id", clientSecret: "test-client-secret")
            },
            saveCredentials: { _ in true },
            loadAuthTokens: { self.tokens },
            saveAuthTokens: { tokens in
                self.saveCount += 1
                self.tokens = tokens
                return true
            },
            deleteAuthTokens: {
                self.deleteCount += 1
                self.tokens = KeychainHelper.AuthTokens()
                return true
            }
        )
    }
}
