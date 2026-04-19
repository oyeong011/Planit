#if os(iOS)
import Foundation
import CalenShared

// MARK: - AIError

/// iOS AI 호출에서 발생할 수 있는 오류 집합. v0.1.1부터 실호출이 생기면 `.network` / `.decoding`
/// / `.apiError`가 실제로 throw된다. v0.1.0(스텁)에서는 `.apiKeyMissing` / `.notYetImplemented`만.
public enum AIError: Error, Equatable {
    /// Keychain에 Claude API 키가 저장돼 있지 않음.
    case apiKeyMissing
    /// v0.1.0 스텁 — URLSession 기반 Messages API 호출은 v0.1.1에서 구현.
    case notYetImplemented
    /// 전송/네트워크 실패 (`URLSession` error).
    case network(Error)
    /// 응답 JSON 디코딩 실패.
    case decoding(Error)
    /// 2xx 이외 HTTP 응답. `status`와 `body`(truncated 가능) 포함.
    case apiError(status: Int, body: String)

    // MARK: Equatable (Error associated values는 Equatable 합성이 안 되므로 수동 구현)

    public static func == (lhs: AIError, rhs: AIError) -> Bool {
        switch (lhs, rhs) {
        case (.apiKeyMissing, .apiKeyMissing),
             (.notYetImplemented, .notYetImplemented):
            return true
        case let (.apiError(l, lb), .apiError(r, rb)):
            return l == r && lb == rb
        case (.network, .network),
             (.decoding, .decoding):
            // Error prototype만 비교 — 타입 매칭으로 충분
            return true
        default:
            return false
        }
    }
}

// MARK: - ClaudeAPIKeyProvider

/// Claude Messages API를 직접 호출할 iOS 전용 `PlanningAIProvider` 스텁.
///
/// v0.1.0(현재):
///   - API 키 유무만 확인. 있으면 `.notYetImplemented`, 없으면 `.apiKeyMissing` throw.
///
/// v0.1.1(예정):
///   - `URLSession`으로 `https://api.anthropic.com/v1/messages` 호출.
///   - 성공 시 `content[0].text` 파싱해 반환.
///   - 실패 시 `.network` / `.decoding` / `.apiError` 로 매핑.
///
/// 키 공급은 클로저 기반 — Settings에서 Keychain (`ClaudeAPIKeychain`)을 통해 읽은 값을
/// 생성자로 넘긴다. 키가 교체되는 경우에도 매 호출 시 최신 값을 조회하기 위함.
@MainActor
public final class ClaudeAPIKeyProvider: PlanningAIProvider {

    // MARK: Properties

    private let apiKeyProvider: () -> String?

    // MARK: Init

    /// - Parameter apiKeyProvider: 매 호출 시 Keychain에서 최신 API 키를 읽는 클로저.
    ///   `nil`이면 키 미설정으로 간주.
    public init(apiKeyProvider: @escaping () -> String?) {
        self.apiKeyProvider = apiKeyProvider
    }

    // MARK: - PlanningAIProvider

    public func sendPlanningRequest(prompt: String) async throws -> String {
        // v0.1.0 스텁 — 키 유무만 검증.
        guard let key = apiKeyProvider(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.apiKeyMissing
        }
        _ = prompt  // v0.1.1에서 요청 body 구성에 사용.
        _ = key     // v0.1.1에서 `x-api-key` 헤더로 사용.
        throw AIError.notYetImplemented
    }
}
#endif
