import Foundation

// MARK: - PlanningAIProvider

/// Planning orchestrator가 기대하는 AI 호출 인터페이스 — 플랫폼 중립.
///
/// macOS: `AIService` (Claude/Codex CLI) 가 준수.
/// iOS: 향후 HTTPS API 어댑터가 준수.
///
/// 기존 `PlanningAIClient`(macOS internal)과 동일한 시그니처를 공유하므로
/// `AIService`가 두 프로토콜을 모두 준수해도 ambiguity 없이 컴파일된다.
/// M2 이후 `PlanningAIClient`를 제거하고 이 타입으로 단일화 예정.
@MainActor
public protocol PlanningAIProvider: AnyObject {
    /// 주어진 프롬프트를 AI에 전달해 단일 응답 문자열을 반환한다.
    /// 부작용(UI 업데이트, 로깅 외)은 없어야 한다.
    func sendPlanningRequest(prompt: String) async throws -> String
}
