import Foundation
import CalenShared

// MARK: - AIService: PlanningAIProvider conformance
//
// Shared 계층(`CalenShared`)이 요구하는 `PlanningAIProvider` 프로토콜을 macOS `AIService`가
// 그대로 만족시킨다. 기존 internal `PlanningAIClient`과 시그니처가 동일
// (`@MainActor func sendPlanningRequest(prompt:) async throws -> String`)하므로
// 본체 수정 없이 conformance만 선언한다.
//
// M2 이후 internal `PlanningAIClient`는 제거되고 `PlanningAIProvider`로 단일화될 예정.
extension AIService: PlanningAIProvider {}
