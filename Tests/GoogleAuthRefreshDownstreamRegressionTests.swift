import Foundation
import Testing

private enum GoogleAuthRefreshDownstreamSource {
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func read(_ path: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func body(of functionName: String, in source: String) throws -> String {
        guard let nameRange = source.range(of: "func \(functionName)") else {
            throw NSError(domain: "GoogleAuthRefreshDownstreamSource", code: 1)
        }
        guard let openingBrace = source[nameRange.lowerBound...].firstIndex(of: "{") else {
            throw NSError(domain: "GoogleAuthRefreshDownstreamSource", code: 2)
        }
        return try braceBlock(openingAt: openingBrace, in: source)
    }

    static func braceBlock(openingAt openingBrace: String.Index, in source: String) throws -> String {
        var depth = 0
        var cursor = openingBrace
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }
        throw NSError(domain: "GoogleAuthRefreshDownstreamSource", code: 3)
    }

    static func segment(from startNeedle: String, to endNeedle: String, in source: String) throws -> String {
        guard let start = source.range(of: startNeedle)?.lowerBound else {
            throw NSError(domain: "GoogleAuthRefreshDownstreamSource", code: 4)
        }
        guard let end = source.range(of: endNeedle, range: start..<source.endIndex)?.lowerBound else {
            throw NSError(domain: "GoogleAuthRefreshDownstreamSource", code: 5)
        }
        return String(source[start..<end])
    }
}

@Suite("Google auth refresh downstream regressions")
struct GoogleAuthRefreshDownstreamRegressionTests {
    @Test("shared client accessToken keeps refresh delegation intentionally local")
    func sharedClientAccessTokenKeepsRefreshDelegationIntentionallyLocal() throws {
        let source = try GoogleAuthRefreshDownstreamSource.read(
            "Shared/Sources/CalenShared/Networking/GoogleCalendarClient.swift"
        )
        let body = try GoogleAuthRefreshDownstreamSource.body(of: "accessToken", in: source)

        #expect(body.contains("try? await authProvider.refreshIfNeeded()"))
        #expect(body.contains("await authProvider.currentAccessToken"))
        #expect(body.contains("GoogleCalendarClientError.noAccessToken"))
        #expect(!body.contains("OAuthRefreshErrorClassifier"))
        #expect(body.range(of: "refreshIfNeeded()")?.lowerBound ?? body.endIndex
            < body.range(of: "currentAccessToken")?.lowerBound ?? body.startIndex)
    }

    @Test("calendar API validation is not coupled to OAuth refresh classification")
    func calendarAPIValidationIsNotCoupledToOAuthRefreshClassification() throws {
        let source = try GoogleAuthRefreshDownstreamSource.read(
            "Shared/Sources/CalenShared/Networking/GoogleCalendarClient.swift"
        )
        let body = try GoogleAuthRefreshDownstreamSource.body(of: "validate", in: source)

        #expect(!body.contains("OAuthRefreshErrorClassifier"))
        #expect(body.contains("case 401:"))
        #expect(body.contains("throw GoogleCalendarClientError.unauthorized"))
        #expect(body.contains("case 403:"))
        #expect(body.contains("throw GoogleCalendarClientError.forbidden"))
        #expect(!body.contains("logout"))
    }

    @Test("legacy calendar list 401 and 403 fallback remains a watched compatibility path")
    func legacyCalendarListFallbackRemainsWatchedCompatibilityPath() throws {
        let source = try GoogleAuthRefreshDownstreamSource.read(
            "Planit/Services/GoogleCalendarService.swift"
        )
        let body = try GoogleAuthRefreshDownstreamSource.body(of: "fetchCalendarList", in: source)
        let fallback = try GoogleAuthRefreshDownstreamSource.segment(
            from: "if statusCode == 403 || statusCode == 401",
            to: "guard (200...299).contains(statusCode)",
            in: body
        )

        #expect(fallback.contains("using primary calendar silently"))
        #expect(fallback.contains(#"GoogleCalendarInfo(id: "primary""#))
        #expect(fallback.contains("cachedCalendars = [primary]"))
        #expect(!fallback.contains("OAuthRefreshErrorClassifier"))
        #expect(!fallback.contains("logout"))
    }
}
