import Foundation

// MARK: - CalendarAuthProviding

/// Google Calendar 등 외부 캘린더 네트워킹 코드가 의존하는 최소 OAuth 인터페이스.
///
/// 구체 `GoogleAuthManager`(macOS Keychain 기반) 대신 이 프로토콜을 주입하면,
/// iOS(ASWebAuthenticationSession 기반)에서도 동일 네트워킹 계층을 공유 가능.
///
/// - Note: property 이름을 `currentAccessToken`으로 둔 이유는 구체 클래스들이
///   이미 `accessToken` 이라는 stored property를 갖고 있어 재선언 충돌을 피하기 위함.
public protocol CalendarAuthProviding: AnyObject {
    /// 현재 저장된(또는 방금 갱신된) 유효 액세스 토큰. 실패 시 nil.
    var currentAccessToken: String? { get async }

    /// 필요 시 토큰 갱신(refresh) 수행. 이미 유효하면 no-op. 실패 시 throw.
    func refreshIfNeeded() async throws
}
