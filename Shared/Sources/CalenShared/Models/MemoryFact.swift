import Foundation

// MARK: - MemoryCategory

/// Hermes 메모리 분류 — 플랫폼 중립 value type.
///
/// macOS/iOS 앱이 공유하며 CloudKit CKRecord 인코딩의 기준이 된다.
public enum MemoryCategory: String, Codable, Sendable, CaseIterable {
    case preference         // 선호 시간대, 집중 패턴
    case schedulePattern    // 반복 일정 패턴
    case habitPattern       // 습관 성공/실패 패턴
    case goalPriority       // 목표 우선순위 신호
    case planningHistory    // 이전 계획 결정 이력
    case communicationStyle // 선호 응답 스타일

    public var displayName: String {
        switch self {
        case .preference:         return "선호"
        case .schedulePattern:    return "일정 패턴"
        case .habitPattern:       return "습관 패턴"
        case .goalPriority:       return "목표 우선순위"
        case .planningHistory:    return "계획 이력"
        case .communicationStyle: return "소통 스타일"
        }
    }
}

// MARK: - MemoryFact

/// Hermes가 학습한 하나의 사실 — 플랫폼 중립 value type.
public struct MemoryFact: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let category: MemoryCategory
    public let key: String
    public let value: String
    public var confidence: Double   // 0.0 ~ 1.0
    public var updatedAt: Date
    public var source: String       // "chat", "review", "habit", "manual", "ios"

    public init(
        id: UUID = UUID(),
        category: MemoryCategory,
        key: String,
        value: String,
        confidence: Double = 0.7,
        source: String = "chat",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.key = key
        self.value = value
        self.confidence = min(1.0, max(0.0, confidence))
        self.source = source
        self.updatedAt = updatedAt
    }
}

// MARK: - PlanningDecision

/// Planning orchestrator가 내린 한 번의 결정 (accept/reject/partial).
public struct PlanningDecision: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let intent: String
    public let summary: String
    public let outcome: DecisionOutcome
    public let recordedAt: Date
    public var learnedFacts: [MemoryFact]

    public enum DecisionOutcome: String, Sendable, Codable {
        case accepted
        case rejected
        case partial
    }

    public init(
        id: UUID = UUID(),
        intent: String,
        summary: String,
        outcome: DecisionOutcome,
        recordedAt: Date = Date(),
        learnedFacts: [MemoryFact] = []
    ) {
        self.id = id
        self.intent = intent
        self.summary = summary
        self.outcome = outcome
        self.recordedAt = recordedAt
        self.learnedFacts = learnedFacts
    }
}
