import Foundation
import Testing
@testable import CalenShared

struct OAuthRefreshErrorClassificationTests {

    @Test("invalid_grant is a permanent revocation")
    func invalidGrantIsPermanentRevocation() {
        let result = OAuthRefreshErrorClassifier.classify(
            statusCode: 400,
            body: oauthErrorBody("invalid_grant")
        )

        #expect(result == .permanentRevocation)
    }

    @Test("non-revocation OAuth terminal errors preserve tokens")
    func nonRevocationOAuthErrorsAreTerminalWithoutRevocation() {
        let terminalErrors = [
            "invalid_client",
            "unauthorized_client",
            "invalid_request",
            "unsupported_grant_type",
            "invalid_scope"
        ]

        for error in terminalErrors {
            let result = OAuthRefreshErrorClassifier.classify(
                statusCode: 400,
                body: oauthErrorBody(error)
            )

            #expect(result == .nonRevocationTerminal)
        }
    }

    @Test("JSON OAuth error classification wins over bare HTTP status")
    func jsonErrorClassificationWinsOverHTTPStatus() {
        let revokedResult = OAuthRefreshErrorClassifier.classify(
            statusCode: 500,
            body: oauthErrorBody("invalid_grant")
        )
        let terminalResult = OAuthRefreshErrorClassifier.classify(
            statusCode: 403,
            body: oauthErrorBody("invalid_client")
        )

        #expect(revokedResult == .permanentRevocation)
        #expect(terminalResult == .nonRevocationTerminal)
    }

    @Test("bare or non-JSON HTTP authorization failures are retryable and token-preserving")
    func bareAuthorizationStatusFailuresAreRetryableTransient() {
        let cases: [(Int, Data)] = [
            (401, Data()),
            (401, Data("<html>unauthorized</html>".utf8)),
            (403, Data("<html>forbidden</html>".utf8))
        ]

        for (statusCode, body) in cases {
            let result = OAuthRefreshErrorClassifier.classify(
                statusCode: statusCode,
                body: body
            )

            #expect(result == .retryableTransient)
        }
    }

    @Test("shared classifier locks the iOS refresh classification parity matrix")
    func sharedClassifierMatchesIOSRefreshMatrix() {
        let cases: [(String, Int, Data, OAuthRefreshClassification)] = [
            ("invalid_grant", 400, oauthErrorBody("invalid_grant"), .permanentRevocation),
            ("invalid_client", 401, oauthErrorBody("invalid_client"), .nonRevocationTerminal),
            ("unauthorized_client", 400, oauthErrorBody("unauthorized_client"), .nonRevocationTerminal),
            ("invalid_request", 400, oauthErrorBody("invalid_request"), .nonRevocationTerminal),
            ("unsupported_grant_type", 400, oauthErrorBody("unsupported_grant_type"), .nonRevocationTerminal),
            ("invalid_scope", 400, oauthErrorBody("invalid_scope"), .nonRevocationTerminal),
            ("non-json 401", 401, Data("<html>unauthorized</html>".utf8), .retryableTransient),
            ("non-json 403", 403, Data("<html>forbidden</html>".utf8), .retryableTransient)
        ]

        for (name, statusCode, body, expected) in cases {
            let result = OAuthRefreshErrorClassifier.classify(
                statusCode: statusCode,
                body: body
            )

            #expect(result == expected, "\(name) should classify as \(expected)")
        }
    }

    @Test("server errors are retryable and token-preserving")
    func serverErrorsAreRetryableTransient() {
        for statusCode in [500, 502, 503, 504] {
            let result = OAuthRefreshErrorClassifier.classify(
                statusCode: statusCode,
                body: Data("temporarily unavailable".utf8)
            )

            #expect(result == .retryableTransient)
        }
    }

    @Test("transport timeouts and offline errors are retryable and token-preserving")
    func transportTimeoutsAndOfflineErrorsAreRetryableTransient() {
        let errors = [
            URLError(.timedOut),
            URLError(.notConnectedToInternet)
        ]

        for error in errors {
            let result = OAuthRefreshErrorClassifier.classify(transportError: error)

            #expect(result == .retryableTransient)
        }
    }

    @Test("malformed JSON is retryable and token-preserving")
    func malformedJSONIsRetryableTransient() {
        let result = OAuthRefreshErrorClassifier.classify(
            statusCode: 200,
            body: Data("{\"access_token\":".utf8)
        )

        #expect(result == .retryableTransient)
    }

    @Test("missing access token is retryable and token-preserving")
    func missingAccessTokenIsRetryableTransient() {
        let result = OAuthRefreshErrorClassifier.classify(
            statusCode: 200,
            body: Data(#"{"expires_in":3600}"#.utf8)
        )

        #expect(result == .retryableTransient)
    }

    @Test("successful token JSON is classified as success")
    func accessTokenResponseIsSuccess() {
        let result = OAuthRefreshErrorClassifier.classify(
            statusCode: 200,
            body: Data(#"{"access_token":"new-token","expires_in":3600}"#.utf8)
        )

        #expect(result == .success)
    }

    private func oauthErrorBody(_ error: String) -> Data {
        Data(#"{"error":"\#(error)","error_description":"description"}"#.utf8)
    }
}
