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

// MARK: - Planning Intent / Context / Suggestion / Action

enum PlanningIntent: String, Codable, Sendable {
    case replanDay
    case fillFreeSlots
    case rescheduleUrgent
    case buildWeekPlan
    case categorizeUntagged   // 카테고리 없는 이벤트 일괄 분류

    var displayName: String {
        switch self {
        case .replanDay:          return "오늘 다시 짜기"
        case .fillFreeSlots:      return "빈 시간 채우기"
        case .rescheduleUrgent:   return "급한 일정 재배치"
        case .buildWeekPlan:      return "이번 주 계획"
        case .categorizeUntagged: return "미분류 일정 분류"
        }
    }
}

/// @MainActor 격리 — Sendable 선언하지 않음 (nested model들이 아직 Sendable 아님).
@MainActor
struct PlanningContext {
    let currentDate: Date
    let todayEvents: [CalendarEvent]
    let nearbyEvents: [CalendarEvent]
    let todos: [TodoItem]
    let recalledMemories: [MemoryFact]
    let userProfile: UserProfile?
    // categorizeUntagged intent 전용
    let untaggedEvents: [CalendarEvent]
    let availableCategories: [TodoCategory]
    // fillFreeSlots intent 전용 — 오늘 남은 빈 시간대
    let freeSlots: [(start: Date, end: Date)]

    init(currentDate: Date,
         todayEvents: [CalendarEvent] = [],
         nearbyEvents: [CalendarEvent] = [],
         todos: [TodoItem] = [],
         recalledMemories: [MemoryFact] = [],
         userProfile: UserProfile? = nil,
         untaggedEvents: [CalendarEvent] = [],
         availableCategories: [TodoCategory] = [],
         freeSlots: [(start: Date, end: Date)] = []) {
        self.currentDate = currentDate
        self.todayEvents = todayEvents
        self.nearbyEvents = nearbyEvents
        self.todos = todos
        self.recalledMemories = recalledMemories
        self.userProfile = userProfile
        self.untaggedEvents = untaggedEvents
        self.availableCategories = availableCategories
        self.freeSlots = freeSlots
    }
}

// AI 응답 파싱용 DTO — 전부 optional, validation은 Orchestrator에서.
struct PlanningSuggestionDTO: Decodable {
    let summary: String?
    let rationale: String?
    let actions: [SuggestedActionDTO]?
    let warnings: [String]?
}

struct SuggestedActionDTO: Decodable {
    let kind: String?
    let title: String?
    let startDate: String?
    let endDate: String?
    let eventID: String?
    let todoID: String?
    let calendarID: String?
    let reason: String?
    let oldStartDate: String?
    let oldTitle: String?
    let categoryName: String?   // categorize action 전용
}

struct PlanningSuggestion: Identifiable {
    let id: UUID
    let intent: PlanningIntent
    let summary: String
    let rationale: String
    let actions: [SuggestedAction]
    let warnings: [String]

    init(id: UUID = UUID(), intent: PlanningIntent, summary: String, rationale: String, actions: [SuggestedAction], warnings: [String]) {
        self.id = id
        self.intent = intent
        self.summary = summary
        self.rationale = rationale
        self.actions = actions
        self.warnings = warnings
    }
}

struct SuggestedAction: Identifiable {
    let id: UUID
    let kind: ActionKind
    let title: String
    let startDate: Date?
    let endDate: Date?
    let eventID: String?
    let todoID: UUID?
    let calendarID: String?
    let reason: String
    let oldStartDate: Date?
    let oldTitle: String?

    enum ActionKind: String, Codable, Sendable, CaseIterable {
        case create, move, delete
        case createTodo, moveTodo, updateTodo
        case categorize   // 기존 이벤트에 카테고리 부여 (제목/시간 변경 없음)

        var displayName: String {
            switch self {
            case .create:     return "새 일정"
            case .move:       return "일정 이동"
            case .delete:     return "일정 삭제"
            case .createTodo: return "할 일 추가"
            case .moveTodo:   return "할 일 이동"
            case .updateTodo: return "할 일 수정"
            case .categorize: return "카테고리"
            }
        }

        var icon: String {
            switch self {
            case .create:     return "plus.circle"
            case .move:       return "arrow.right.circle"
            case .delete:     return "minus.circle"
            case .createTodo: return "checklist"
            case .moveTodo:   return "arrow.right.square"
            case .updateTodo: return "pencil.circle"
            case .categorize: return "tag.circle"
            }
        }
    }

    /// categorize action 전용 — 검증된 카테고리 ID (이름 재해석 없이 바로 적용)
    let categoryID: UUID?

    init(id: UUID = UUID(), kind: ActionKind, title: String,
         startDate: Date? = nil, endDate: Date? = nil,
         eventID: String? = nil, todoID: UUID? = nil,
         calendarID: String? = nil, reason: String = "",
         oldStartDate: Date? = nil, oldTitle: String? = nil,
         categoryID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.eventID = eventID
        self.todoID = todoID
        self.calendarID = calendarID
        self.reason = reason
        self.oldStartDate = oldStartDate
        self.oldTitle = oldTitle
        self.categoryID = categoryID
    }
}

enum PlanningError: LocalizedError {
    case cliUnavailable
    case invalidResponse
    case noActionsProposed

    var errorDescription: String? {
        switch self {
        case .cliUnavailable:    return "AI CLI가 설정되지 않았습니다. 설정에서 Claude 또는 Codex를 연결하세요."
        case .invalidResponse:   return "AI 응답을 해석할 수 없습니다."
        case .noActionsProposed: return "제안할 변경사항이 없습니다."
        }
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
