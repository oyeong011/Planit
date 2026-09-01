import Foundation
import Testing
@testable import Calen

@Suite("Auth error localization")
struct AuthErrorLocalizationTests {
    @Test("auth refresh failure messages resolve from the module bundle")
    func authRefreshFailureMessagesResolve() {
        for key in authRefreshKeys {
            let value = String(localized: String.LocalizationValue(key), bundle: .module)

            #expect(value != key, "\(key) resolved to a raw localization key")
            #expect(!value.isEmpty, "\(key) resolved to an empty string")
            #expect(!value.contains("auth.refresh."), "\(key) still exposes an auth.refresh raw key")
        }
    }

    @Test("GoogleAuthManager publishes localized refresh failure messages")
    func googleAuthManagerPublishesLocalizedRefreshFailureMessages() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Planit/Services/GoogleAuthManager.swift"),
            encoding: .utf8
        )

        for key in authRefreshKeys {
            #expect(
                source.contains(#"errorMessage = String(localized: "\#(key)", bundle: .module)"#),
                "GoogleAuthManager should localize \(key) before publishing errorMessage"
            )
            #expect(
                !source.contains(#"errorMessage = "\#(key)""#),
                "GoogleAuthManager should not publish raw \(key)"
            )
        }
    }

    private var authRefreshKeys: [String] {
        [
            "auth.refresh.permanent_revocation",
            "auth.refresh.non_revocation_terminal",
            "auth.refresh.retryable_transient"
        ]
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
