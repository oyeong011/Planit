import Foundation

// MARK: - Goal Level

enum GoalLevel: String, Codable, CaseIterable {
    case year = "year"
    case quarter = "quarter"
    case month = "month"
    case week = "week"
}

// MARK: - Goal

struct Goal: Identifiable, Codable {
    let id: String
    var parentId: String?
    var level: GoalLevel
    var title: String
    var description: String
    var startDate: Date
    var dueDate: Date
    var weight: Int  // 1-5
    var targetHours: Double?
    var status: GoalStatus
    var recurrence: RecurrencePlan?
    var preferredTimeTags: [String]  // "AM-Deep", "PM-Light", etc.
    var minSessionMinutes: Int
    var maxPerDaySessions: Int
    var createdAt: Date

    init(id: String = UUID().uuidString, parentId: String? = nil, level: GoalLevel,
         title: String, description: String = "", startDate: Date = Date(),
         dueDate: Date, weight: Int = 3, targetHours: Double? = nil,
         status: GoalStatus = .active, recurrence: RecurrencePlan? = nil,
         preferredTimeTags: [String] = ["AM-Deep"],
         minSessionMinutes: Int = 30, maxPerDaySessions: Int = 2) {
        self.id = id
        self.parentId = parentId
        self.level = level
        self.title = title
        self.description = description
        self.startDate = startDate
        self.dueDate = dueDate
        self.weight = weight
        self.targetHours = targetHours
        self.status = status
        self.recurrence = recurrence
        self.preferredTimeTags = preferredTimeTags
        self.minSessionMinutes = minSessionMinutes
        self.maxPerDaySessions = maxPerDaySessions
        self.createdAt = Date()
    }
}

enum GoalStatus: String, Codable {
    case active, paused, done
}

// MARK: - Recurrence Plan

struct RecurrencePlan: Codable {
    var weeklyTargetSessions: Int  // e.g., 4
    var perSessionMinutes: Int     // e.g., 60
    var allowedDays: [Int]         // 1=Mon ... 7=Sun
}

// MARK: - Completion Record

struct CompletionRecord: Identifiable, Codable {
    let id: String
    var eventId: String  // Google Calendar event ID
    var eventTitle: String?  // 사람이 읽을 수 있는 이벤트 제목 (알림/리뷰에 표시)
    var goalId: String?
    var date: Date
    var status: CompletionStatus
    var plannedMinutes: Int
    var actualMinutes: Int?
    var note: String?

    init(id: String = UUID().uuidString, eventId: String, eventTitle: String? = nil,
         goalId: String? = nil, date: Date = Date(), status: CompletionStatus = .unknown,
         plannedMinutes: Int = 0, actualMinutes: Int? = nil, note: String? = nil) {
        self.id = id
        self.eventId = eventId
        self.eventTitle = eventTitle
        self.goalId = goalId
        self.date = date
        self.status = status
        self.plannedMinutes = plannedMinutes
        self.actualMinutes = actualMinutes
        self.note = note
    }
}

enum CompletionStatus: String, Codable {
    case unknown, done, skipped, partial, moved
}

// MARK: - User Profile

struct UserProfile: Codable {
    var workStartHour: Int       // e.g., 9
    var workEndHour: Int         // e.g., 18
    var commuteMinutes: Int      // one-way
    var lunchStartHour: Int      // e.g., 12
    var lunchEndHour: Int        // e.g., 13
    var energyType: EnergyType
    var weekdayCapacityMinutes: Int   // max focus minutes per weekday
    var weekendCapacityMinutes: Int
    var morningBriefHour: Int    // e.g., 8
    var eveningReviewHour: Int   // e.g., 21
    var aggressiveness: Aggressiveness
    var usesFocusWindowsForAI: Bool
    var onboardingDone: Bool

    init() {
        workStartHour = 9
        workEndHour = 18
        commuteMinutes = 30
        lunchStartHour = 12
        lunchEndHour = 13
        energyType = .morning
        weekdayCapacityMinutes = 120
        weekendCapacityMinutes = 180
        morningBriefHour = 8
        eveningReviewHour = 21
        aggressiveness = .manual
        usesFocusWindowsForAI = true
        onboardingDone = false
    }

    enum CodingKeys: String, CodingKey {
        case workStartHour
        case workEndHour
        case commuteMinutes
        case lunchStartHour
        case lunchEndHour
        case energyType
        case weekdayCapacityMinutes
        case weekendCapacityMinutes
        case morningBriefHour
        case eveningReviewHour
        case aggressiveness
        case usesFocusWindowsForAI
        case onboardingDone
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UserProfile()
        workStartHour = try values.decodeIfPresent(Int.self, forKey: .workStartHour) ?? defaults.workStartHour
        workEndHour = try values.decodeIfPresent(Int.self, forKey: .workEndHour) ?? defaults.workEndHour
        commuteMinutes = try values.decodeIfPresent(Int.self, forKey: .commuteMinutes) ?? defaults.commuteMinutes
        lunchStartHour = try values.decodeIfPresent(Int.self, forKey: .lunchStartHour) ?? defaults.lunchStartHour
        lunchEndHour = try values.decodeIfPresent(Int.self, forKey: .lunchEndHour) ?? defaults.lunchEndHour
        energyType = try values.decodeIfPresent(EnergyType.self, forKey: .energyType) ?? defaults.energyType
        weekdayCapacityMinutes = try values.decodeIfPresent(Int.self, forKey: .weekdayCapacityMinutes) ?? defaults.weekdayCapacityMinutes
        weekendCapacityMinutes = try values.decodeIfPresent(Int.self, forKey: .weekendCapacityMinutes) ?? defaults.weekendCapacityMinutes
        morningBriefHour = try values.decodeIfPresent(Int.self, forKey: .morningBriefHour) ?? defaults.morningBriefHour
        eveningReviewHour = try values.decodeIfPresent(Int.self, forKey: .eveningReviewHour) ?? defaults.eveningReviewHour
        aggressiveness = try values.decodeIfPresent(Aggressiveness.self, forKey: .aggressiveness) ?? defaults.aggressiveness
        usesFocusWindowsForAI = try values.decodeIfPresent(Bool.self, forKey: .usesFocusWindowsForAI) ?? defaults.usesFocusWindowsForAI
        onboardingDone = try values.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? defaults.onboardingDone
    }
}

enum EnergyType: String, Codable, CaseIterable {
    case morning = "아침형"
    case evening = "저녁형"
    case balanced = "균형형"

    var localizedTitle: String {
        switch self {
        case .morning:  return NSLocalizedString("energy.type.morning", comment: "")
        case .evening:  return NSLocalizedString("energy.type.evening", comment: "")
        case .balanced: return NSLocalizedString("energy.type.balanced", comment: "")
        }
    }

    var deepSlots: [String] {
        switch self {
        case .morning: return ["AM-Deep"]
        case .evening: return ["PM-Deep"]
        case .balanced: return ["AM-Deep", "PM-Deep"]
        }
    }
}

enum Aggressiveness: String, Codable, CaseIterable {
    case manual = "수동"
    case assist = "보조"
    case semiAuto = "반자동"
    case auto = "자동"

    var localizedTitle: String {
        switch self {
        case .manual:   return NSLocalizedString("aggressiveness.manual", comment: "")
        case .assist:   return NSLocalizedString("aggressiveness.assist", comment: "")
        case .semiAuto: return NSLocalizedString("aggressiveness.semiauto", comment: "")
        case .auto:     return NSLocalizedString("aggressiveness.auto", comment: "")
        }
    }
}

// MARK: - Review Suggestion

struct ReviewSuggestion: Identifiable {
    let id = UUID()
    var type: SuggestionType
    var title: String
    var description: String
    var goalId: String?
    var sourceEventId: String?   // 원본 CalendarEvent.id (completionFor 조회 키로 사용)
    var proposedStart: Date?
    var proposedEnd: Date?
    var proposedTitle: String?   // 새로 생성할 이벤트 제목 (표시용)
    var status: SuggestionStatus = .pending
}

enum SuggestionType: String {
    case carryover     // 미완료 이월
    case deadline      // 데드라인 임박
    case habitGap      // 습관 갭
    case deadlineSpread // 마감 분산
    case prep          // 미팅 준비
    case focusQuota    // 집중 쿼터
    case health        // 건강 (연속 회의)
    case buffer        // 이동 버퍼
}

enum SuggestionStatus: String {
    case pending, accepted, declined, edited
}

// MARK: - Daily Metrics

struct DailyMetrics: Codable {
    var date: Date
    var plannedCount: Int
    var completedCount: Int
    var movedCount: Int
    var skippedCount: Int
    var totalPlannedMinutes: Int
    var totalActualMinutes: Int
}
