import Foundation

// MARK: - ClaudePlanningAIProvider
//
// `ClaudeAPIClient`를 `PlanningAIProvider`로 노출하는 어댑터.
//
// 역할:
//   - prompt 하나를 받아 non-streaming 호출로 전체 assistant 텍스트를 모아 반환.
//   - 스트리밍이 필요 없는 planning 용도 (응답 전체를 한 번에 JSON 파싱).
//
// 책임 분리:
//   - HTTP/SSE / 에러 매핑 = `ClaudeAPIClient` (actor)
//   - 프롬프트 빌드 / 응답 파싱 = `PlanningOrchestrator`
//   - 본 어댑터 = 단순 위임

/// `ClaudeAPIClient`를 `PlanningAIProvider`로 감싼 어댑터.
///
/// `sendPlanningRequest(prompt:)`는 non-streaming 모드로 한 번의 메시지를 보내고
/// assistant content text 블록들을 이어붙여 반환한다.
@MainActor
public final class ClaudePlanningAIProvider: PlanningAIProvider {

    private let client: ClaudeAPIClient
    private let system: String

    /// - Parameters:
    ///   - client: 이미 구성된 `ClaudeAPIClient` (API 키 provider 포함).
    ///   - system: 선택 시스템 프롬프트. nil이면 기본 planning 가이드.
    public init(client: ClaudeAPIClient, system: String? = nil) {
        self.client = client
        self.system = system ?? Self.defaultSystemPrompt
    }

    /// planning 용 기본 시스템 프롬프트. "엄격한 JSON만" 원칙 강화.
    public static let defaultSystemPrompt: String = """
    당신은 Calen 캘린더 앱의 Planning 에이전트입니다.
    오직 유효한 JSON 객체 하나만 응답하세요.
    코드펜스(```) 또는 설명 문장을 섞지 마세요.
    """

    public func sendPlanningRequest(prompt: String) async throws -> String {
        // non-streaming 모드 — messageStart / 한 번의 contentBlockDelta / messageStop 순으로 오므로
        // contentBlockDelta 의 텍스트를 누적해 반환.
        let stream = await client.send(
            messages: [.user(prompt)],
            system: system,
            stream: false
        )

        var accumulated = ""
        do {
            for try await event in stream {
                switch event {
                case .messageStart:
                    break
                case let .contentBlockDelta(text):
                    accumulated += text
                case .messageStop:
                    break
                }
            }
        } catch {
            // ClaudeAPIError 를 그대로 상위로 전파 — 호출자(TodayReplanService)에서 userMessage 매핑.
            throw error
        }
        return accumulated
    }
}
