import Foundation

// MARK: - CalendarAuthProviding

/// Google Calendar 등 외부 캘린더 네트워킹 코드가 의존하는 최소 OAuth 인터페이스.
///
/// 구체 `GoogleAuthManager`(macOS Keychain 기반) 대신 이 프로토콜을 주입하면,
/// iOS(ASWebAuthenticationSession 기반)에서도 동일 네트워킹 계층을 공유 가능.
public protocol CalendarAuthProviding: AnyObject {
    /// 현재 저장된 액세스 토큰 — 만료 시 nil.
    var accessToken: String? { get async }

    /// 필요 시 토큰 갱신(refresh) 수행. 이미 유효하면 no-op.
    func refreshIfNeeded() async throws
}
