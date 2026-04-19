#if os(iOS)
import Foundation
import SwiftData

// MARK: - Hermes Models (iOS용 — macOS와 정확히 동일한 @Model 스키마)
//
// ⚠️ 주의: macOS의 Planit/Models/HermesModels.swift와 *정확히 같은 구조*여야 합니다.
// CloudKit은 스키마 해시 기반이라 한 쪽이 바뀌면 sync 깨집니다.
// 향후 Shared/Sources/CalenShared로 통합될 예정 (Phase 2).

public enum MemoryCategory: String, Codable, Sendable, CaseIterable {
    case preference, schedulePattern, habitPattern
    case goalPriority, planningHistory, communicationStyle

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

public struct MemoryFact: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let category: MemoryCategory
    public let key: String
    public let value: String
    public var confidence: Double
    public var updatedAt: Date
    public var source: String

    public init(id: UUID = UUID(), category: MemoryCategory, key: String, value: String,
                confidence: Double = 0.7, source: String = "ios",
                updatedAt: Date = Date()) {
        self.id = id
        self.category = category
        self.key = key
        self.value = value
        self.confidence = min(1.0, max(0.0, confidence))
        self.source = source
        self.updatedAt = updatedAt
    }
}

public struct PlanningDecision: Sendable, Identifiable {
    public let id: UUID
    public let intent: String
    public let summary: String
    public let outcome: DecisionOutcome
    public let recordedAt: Date
    public var learnedFacts: [MemoryFact]

    public enum DecisionOutcome: String, Sendable {
        case accepted, rejected, partial
    }

    public init(id: UUID = UUID(), intent: String, summary: String, outcome: DecisionOutcome,
                recordedAt: Date = Date(), learnedFacts: [MemoryFact] = []) {
        self.id = id
        self.intent = intent
        self.summary = summary
        self.outcome = outcome
        self.recordedAt = recordedAt
        self.learnedFacts = learnedFacts
    }
}

// MARK: - SwiftData Records (스키마 — macOS와 필드명·타입 동일해야 함)

@Model
public final class MemoryFactRecord {
    @Attribute(.unique) public var id: UUID
    public var categoryRaw: String
    public var key: String
    public var value: String
    public var confidence: Double
    public var source: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), categoryRaw: String, key: String, value: String,
                confidence: Double, source: String, updatedAt: Date = Date()) {
        self.id = id
        self.categoryRaw = categoryRaw
        self.key = key
        self.value = value
        self.confidence = confidence
        self.source = source
        self.updatedAt = updatedAt
    }

    public func toDomain() -> MemoryFact {
        MemoryFact(
            id: id,
            category: MemoryCategory(rawValue: categoryRaw) ?? .preference,
            key: key, value: value,
            confidence: confidence, source: source,
            updatedAt: updatedAt
        )
    }
}

@Model
public final class PlanningDecisionRecord {
    @Attribute(.unique) public var id: UUID
    public var intent: String
    public var summary: String
    public var outcomeRaw: String
    public var recordedAt: Date
    public var learnedFactsJSON: Data

    public init(id: UUID = UUID(), intent: String, summary: String,
                outcomeRaw: String, recordedAt: Date = Date(),
                learnedFactsJSON: Data = Data()) {
        self.id = id
        self.intent = intent
        self.summary = summary
        self.outcomeRaw = outcomeRaw
        self.recordedAt = recordedAt
        self.learnedFactsJSON = learnedFactsJSON
    }
}
#endif
