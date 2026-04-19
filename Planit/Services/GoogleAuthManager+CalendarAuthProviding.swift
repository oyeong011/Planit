import Foundation
import CalenShared

// MARK: - GoogleAuthManager → CalendarAuthProviding adapter
//
// Shared 네트워킹 계층(M2 이후 Shared로 이동 예정)이 구체 타입 대신
// `CalendarAuthProviding` 프로토콜에 의존할 수 있도록 기존 macOS 구현에
// 최소 conformance를 추가.
//
// 행동:
//  - `accessToken`: 저장된 유효 토큰이 있으면 반환, 없으면 refresh 시도 후 반환.
//    실패(refresh token 없음/네트워크 에러)는 nil.
//  - `refreshIfNeeded()`: getValidToken()을 호출 후 결과를 버림으로써
//    토큰이 만료됐다면 갱신하고, 문제가 있으면 동일 에러를 throw.

extension GoogleAuthManager: CalendarAuthProviding {
    public var currentAccessToken: String? {
        get async {
            return try? await getValidToken()
        }
    }

    public func refreshIfNeeded() async throws {
        _ = try await getValidToken()
    }
}
