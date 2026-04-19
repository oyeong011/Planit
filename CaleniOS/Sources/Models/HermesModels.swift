#if os(iOS)
import Foundation
import SwiftData
// MemoryCategory / MemoryFact / PlanningDecision / PlanningDecision.DecisionOutcome 은
// M1 Step 3에서 Shared로 승격됨. iOS에서도 Shared 것을 그대로 사용.
@_exported import CalenShared

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
