#if os(iOS)
import Foundation

// MARK: - Google OAuth URL handler (iOS)
//
// `ASWebAuthenticationSession`은 `callbackURLScheme`로 앱이 다시 활성화되는 경로를
// 자체적으로 처리하므로, 일반적인 OAuth 로그인에서는 이 핸들러가 호출되지 않는다.
//
// 다만 **외부 앱 → Calen iOS** 로 돌아오는 경로(예: 다른 OAuth 라이브러리 통합,
// Google Chrome `iPhone 앱으로 열기` 등 사용자 토글 케이스)를 위해
// `onOpenURL`에서 호출할 hook을 둔다. UI 팀장이 `CaleniOSApp.swift`의 `onOpenURL` 에서
// 이 static 함수를 호출하면 된다.
//
// 사용 예:
//   ContentView()
//       .onOpenURL { url in
//           GoogleOAuthURLHandler.handleCallback(url)
//       }
enum GoogleOAuthURLHandler {
    /// 대기 중인 OAuth continuation. ASWebAuth가 아닌 외부 redirect 경로를 쓸 때만 설정된다.
    /// (일반 플로우는 `iOSGoogleAuthManager.runWebAuth`가 자체 continuation을 관리한다.)
    @MainActor static var pendingContinuation: CheckedContinuation<URL, Error>?

    /// SwiftUI의 `onOpenURL`에서 호출.
    /// - 반환값: 이 핸들러가 URL을 소비했는지 여부. false면 caller가 다른 경로로 처리해야 함.
    @discardableResult
    @MainActor
    static func handleCallback(_ url: URL) -> Bool {
        guard isGoogleOAuthCallback(url) else { return false }
        if let cont = pendingContinuation {
            pendingContinuation = nil
            cont.resume(returning: url)
            return true
        }
        // continuation이 없는 경우(앱 첫 실행 + 외부 브라우저 리다이렉트 등)는
        // 현재 버전에서는 무시. 추후 deep-link 기반 OAuth가 필요하면 NotificationCenter로
        // 브로드캐스트하도록 확장. (M2 AUTH v0.1.0 범위 밖.)
        return true
    }

    /// reversed-client-ID scheme 패턴 매칭.
    /// 예: `com.googleusercontent.apps.1234567890-abcdef://oauth2redirect`
    static func isGoogleOAuthCallback(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme.hasPrefix("com.googleusercontent.apps.")
    }
}
#endif
