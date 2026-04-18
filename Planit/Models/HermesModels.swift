import Foundation
import SwiftData

// MARK: - MemoryCategory

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

// MARK: - Domain Models (value types — 앱 전체 & 테스트에서 사용)

struct MemoryFact: Sendable, Identifiable, Equatable {
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

struct PlanningDecision: Sendable, Identifiable {
    let id: UUID
    let intent: String
    let summary: String
    let outcome: DecisionOutcome
    let recordedAt: Date
    var learnedFacts: [MemoryFact]

    enum DecisionOutcome: String, Sendable {
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

// MARK: - SwiftData Persistence Models

/// SwiftData 영속 레이어 — MemoryFact 도메인 모델에 대응
@Model
final class MemoryFactRecord {
    @Attribute(.unique) var id: UUID
    var categoryRaw: String
    var key: String
    var value: String
    var confidence: Double
    var source: String
    var updatedAt: Date

    init(_ fact: MemoryFact) {
        self.id = fact.id
        self.categoryRaw = fact.category.rawValue
        self.key = fact.key
        self.value = fact.value
        self.confidence = fact.confidence
        self.source = fact.source
        self.updatedAt = fact.updatedAt
    }

    func toDomain() -> MemoryFact {
        MemoryFact(
            id: id,
            category: MemoryCategory(rawValue: categoryRaw) ?? .preference,
            key: key,
            value: value,
            confidence: confidence,
            source: source,
            updatedAt: updatedAt
        )
    }

    func update(from fact: MemoryFact) {
        value = fact.value
        confidence = fact.confidence
        source = fact.source
        updatedAt = fact.updatedAt
    }
}

/// SwiftData 영속 레이어 — PlanningDecision 도메인 모델에 대응
@Model
final class PlanningDecisionRecord {
    @Attribute(.unique) var id: UUID
    var intent: String
    var summary: String
    var outcomeRaw: String
    var recordedAt: Date
    // learnedFacts는 JSON으로 직렬화 (복잡한 관계 대신 단순화)
    var learnedFactsJSON: Data

    init(_ decision: PlanningDecision) {
        self.id = decision.id
        self.intent = decision.intent
        self.summary = decision.summary
        self.outcomeRaw = decision.outcome.rawValue
        self.recordedAt = decision.recordedAt
        self.learnedFactsJSON = (try? JSONEncoder().encode(decision.learnedFacts.map { MemoryFactDTO($0) })) ?? Data()
    }

    func toDomain() -> PlanningDecision {
        let facts = (try? JSONDecoder().decode([MemoryFactDTO].self, from: learnedFactsJSON))?.map { $0.toFact() } ?? []
        return PlanningDecision(
            id: id,
            intent: intent,
            summary: summary,
            outcome: PlanningDecision.DecisionOutcome(rawValue: outcomeRaw) ?? .rejected,
            recordedAt: recordedAt,
            learnedFacts: facts
        )
    }
}

// learnedFacts 직렬화용 DTO
private struct MemoryFactDTO: Codable {
    let id: UUID
    let categoryRaw: String
    let key: String
    let value: String
    let confidence: Double
    let source: String
    let updatedAt: Date

    init(_ fact: MemoryFact) {
        self.id = fact.id
        self.categoryRaw = fact.category.rawValue
        self.key = fact.key
        self.value = fact.value
        self.confidence = fact.confidence
        self.source = fact.source
        self.updatedAt = fact.updatedAt
    }

    func toFact() -> MemoryFact {
        MemoryFact(
            id: id,
            category: MemoryCategory(rawValue: categoryRaw) ?? .preference,
            key: key,
            value: value,
            confidence: confidence,
            source: source,
            updatedAt: updatedAt
        )
    }
}
