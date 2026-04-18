import Foundation

// MARK: - Memory Category

enum MemoryCategory: String, Codable, Sendable, CaseIterable {
    case preference         // 선호 시간대, 집중 패턴
    case schedulePattern    // 반복 일정 패턴
    case habitPattern       // 습관 성공/실패 패턴
    case goalPriority       // 목표 우선순위 신호
    case planningHistory    // 이전 계획 결정 이력
    case communicationStyle // 선호 응답 스타일

    var displayName: String {
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

// MARK: - Memory Fact

struct MemoryFact: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let category: MemoryCategory
    let key: String
    let value: String
    var confidence: Double   // 0.0 ~ 1.0
    var updatedAt: Date
    var source: String       // "chat", "review", "habit", "manual"

    init(
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

// MARK: - Planning Decision

struct PlanningDecision: Codable, Sendable, Identifiable {
    let id: UUID
    let intent: String       // e.g. "replanDay", "buildWeekPlan"
    let summary: String
    let outcome: DecisionOutcome
    let recordedAt: Date
    var learnedFacts: [MemoryFact]

    enum DecisionOutcome: String, Codable, Sendable {
        case accepted
        case rejected
        case partial
    }

    init(
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
