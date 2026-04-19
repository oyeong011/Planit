import Foundation

// MARK: - PlanningAIProvider

/// Planning orchestrator가 기대하는 AI 호출 인터페이스 — 플랫폼 중립.
///
/// macOS: `AIService` (Claude/Codex CLI) 가 준수.
/// iOS: 향후 HTTPS API 어댑터가 준수.
///
/// 이 프로토콜은 순수 I/O 계약이므로 `Sendable`이며, conformer가 @MainActor든
/// 아니든 상관없이 async-throws 시그니처만 지킨다.
public protocol PlanningAIProvider: Sendable {
    /// 주어진 프롬프트를 AI에 전달해 단일 응답 문자열을 반환한다.
    /// 부작용(UI 업데이트, 로깅 외)은 없어야 한다.
    func completePlanningPrompt(_ prompt: String) async throws -> String
}
