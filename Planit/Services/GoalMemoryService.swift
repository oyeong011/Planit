import Foundation
import SwiftUI

// MARK: - Models

enum GoalTimeline: String, Codable, CaseIterable {
    case thisMonth   = "thisMonth"
    case thisQuarter = "thisQuarter"
    case thisYear    = "thisYear"
    case longTerm    = "longTerm"

    var label: String {
        switch self {
        case .thisMonth:   return String(localized: "goal.timeline.month")
        case .thisQuarter: return String(localized: "goal.timeline.quarter")
        case .thisYear:    return String(localized: "goal.timeline.year")
        case .longTerm:    return String(localized: "goal.timeline.longterm")
        }
    }

    var icon: String {
        switch self {
        case .thisMonth:   return "calendar"
        case .thisQuarter: return "calendar.badge.clock"
        case .thisYear:    return "flag.checkered"
        case .longTerm:    return "star"
        }
    }
}

struct ChatGoal: Codable, Identifiable {
    let id: UUID
    var title: String              // "대기업 IT 취업"
    var targets: [String]          // ["하이닉스", "삼성전자", "농협은행"]
    var keywords: [String]         // 캘린더 이벤트 매칭 키워드
    var timeline: GoalTimeline
    var detectedAt: Date
    // 최근 4주 주별 관련 이벤트 수 (index 0 = 4주전, index 3 = 이번주)
    var weeklyActivity: [Int]
    var lastActivityUpdate: Date

    init(title: String, targets: [String], keywords: [String],
         timeline: GoalTimeline) {
        self.id = UUID()
        self.title = title
        self.targets = targets
        self.keywords = keywords
        self.timeline = timeline
        self.detectedAt = Date()
        self.weeklyActivity = [0, 0, 0, 0]
        self.lastActivityUpdate = Date()
    }
}

// MARK: - GoalDetector Protocol
// Hermes 에이전트 연결 시 이 프로토콜을 구현한 HermesGoalDetector로 교체

protocol GoalDetector: Sendable {
    func detect(in message: String) -> [GoalDraft]
}

struct GoalDraft {
    var title: String
    var targets: [String]
    var keywords: [String]
    var timeline: GoalTimeline
    var confidence: Double
}

// MARK: - Local Keyword Detector (API 없이 동작)

// struct → 저장 프로퍼티가 불변이므로 Sendable 자동 준수
struct LocalKeywordGoalDetector: GoalDetector, Sendable {

    // 목표 의도 감지 트리거
    private let goalTriggers = [
        "목표", "하고싶", "되고싶", "취업하고", "합격하고", "입사하고",
        "이직하고", "원해", "원하는", "꿈", "목표야", "목표입니다",
        "취업이 목표", "합격이 목표", "이직이 목표"
    ]

    // 카테고리별 키워드 + 관련 캘린더 매칭 키워드
    private let categoryMap: [(title: String, triggers: [String], keywords: [String])] = [
        (
            title: "IT 대기업 취업",
            triggers: ["하이닉스", "삼성전자", "카카오", "네이버", "LG전자", "현대", "기아",
                       "농협은행", "국민은행", "신한은행", "우리은행", "포스코", "KT", "SKT",
                       "SK하이닉스", "삼성", "대기업", "IT기업"],
            keywords: ["코딩테스트", "알고리즘", "자소서", "면접", "코테", "포트폴리오",
                       "CS", "자료구조", "네트워크", "운영체제", "데이터베이스"]
        ),
        (
            title: "자격증 취득",
            triggers: ["정보처리기사", "정보보안기사", "SQLD", "AWS", "정처기", "기사",
                       "자격증", "IELTS", "토익", "토플", "TOEIC", "OPIc"],
            keywords: ["기출", "공부", "학습", "모의고사", "시험", "과목", "문제풀이"]
        ),
        (
            title: "공무원 준비",
            triggers: ["공무원", "9급", "7급", "행정직", "기술직", "국가직", "지방직"],
            keywords: ["행정법", "국어", "영어", "한국사", "공무원 공부", "기출"]
        ),
        (
            title: "창업 / 사이드프로젝트",
            triggers: ["창업", "스타트업", "사이드프로젝트", "앱개발", "서비스출시", "MVP"],
            keywords: ["개발", "기획", "디자인", "마케팅", "투자", "피칭"]
        ),
        (
            title: "건강 / 운동",
            triggers: ["헬스", "다이어트", "체중감량", "마라톤", "운동목표", "몸만들기"],
            keywords: ["운동", "헬스", "러닝", "요가", "수영", "필라테스", "식단"]
        ),
        (
            title: "어학 / 해외",
            triggers: ["영어공부", "일본어", "중국어", "어학연수", "해외취업", "유학"],
            keywords: ["영어", "일본어", "중국어", "언어", "공부", "회화"]
        )
    ]

    func detect(in message: String) -> [GoalDraft] {
        let lower = message.lowercased()

        // 1. 목표 의도 트리거 포함 여부
        let hasGoalIntent = goalTriggers.contains { lower.contains($0) }
        guard hasGoalIntent else { return [] }

        var drafts: [GoalDraft] = []

        for category in categoryMap {
            // 대소문자 무시 매칭 (aws, sqld 등 소문자 입력 대응)
            var matchedTriggers = category.triggers.filter { message.localizedCaseInsensitiveContains($0) }
            guard !matchedTriggers.isEmpty else { continue }

            // 중복 제거: "삼성전자"가 있으면 "삼성" 제거 (부분 문자열)
            matchedTriggers = matchedTriggers.filter { t in
                !matchedTriggers.contains { other in other != t && other.localizedCaseInsensitiveContains(t) }
            }

            let confidence = min(Double(matchedTriggers.count) * 0.3 + 0.5, 1.0)
            drafts.append(GoalDraft(
                title: category.title,
                targets: matchedTriggers,
                keywords: category.keywords,
                timeline: detectTimeline(in: message),
                confidence: confidence
            ))
        }

        // 카테고리 미매칭: raw 문장에서 핵심 명사만 추출해 저장
        if drafts.isEmpty {
            let cleanedTitle = extractGoalTitle(from: message)
            if cleanedTitle.count > 2 {
                drafts.append(GoalDraft(
                    title: cleanedTitle,
                    targets: [],
                    keywords: [],
                    timeline: detectTimeline(in: message),
                    confidence: 0.5
                ))
            }
        }

        return drafts.filter { $0.confidence >= 0.4 }
    }

    /// "대학원입학이 올해 목표야" → "대학원 입학" 처럼 핵심만 추출
    private func extractGoalTitle(from message: String) -> String {
        let noisePatterns = [
            "이 올해 목표야", "가 올해 목표야", "이 목표야", "가 목표야",
            "이 목표입니다", "가 목표입니다", "이 내 목표", "이 나의 목표",
            "하고 싶어", "하고싶어", "하고 싶다", "하고싶다",
            "되고 싶어", "되고싶어", "되고 싶다", "되고싶다",
            "올해", "이번 달", "이번달", "이번 분기", "올 해",
            "목표야", "목표입니다", "목표다", "목표에요",
            "이야", "이에요", "입니다", "이다"
        ]
        var result = message
        for noise in noisePatterns {
            result = result.replacingOccurrences(of: noise, with: " ")
        }
        // 공백 정리 + 앞뒤 특수문자 제거
        result = result
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "가-힣a-zA-Z0-9 ")))
        return String(result.prefix(20)).trimmingCharacters(in: .whitespaces)
    }

    private func detectTimeline(in message: String) -> GoalTimeline {
        if message.contains("이번달") || message.contains("이번 달") { return .thisMonth }
        if message.contains("분기") || message.contains("3개월") { return .thisQuarter }
        if message.contains("올해") || message.contains("이번 해") || message.contains("연내") { return .thisYear }
        if message.contains("내년") || message.contains("장기") || message.contains("앞으로") { return .longTerm }
        return .thisYear  // 기본: 올해
    }
}

// MARK: - GoalMemoryService
// Hermes 연결 시: setDetector(HermesGoalDetector(...)) 한 줄로 교체

@MainActor
final class GoalMemoryService: ObservableObject {

    @Published private(set) var goals: [ChatGoal] = []

    private var detector: any GoalDetector = LocalKeywordGoalDetector()
    private let storageKey = "planit.chatGoals.v1"

    init() {
        load()
    }

    // MARK: - Hermes 교체 지점
    // func connectHermes(_ hermesDetector: some GoalDetector) {
    //     self.detector = hermesDetector
    // }

    // MARK: - 메시지 처리

    /// 사용자 채팅 메시지에서 목표 감지 후 저장. 새 목표가 있으면 반환
    @discardableResult
    func processUserMessage(_ message: String) -> [ChatGoal] {
        let drafts = detector.detect(in: message)
        var added: [ChatGoal] = []

        for draft in drafts {
            // 같은 카테고리 목표가 이미 있으면 targets 병합 (중복 저장 방지)
            if let idx = goals.firstIndex(where: { $0.title == draft.title }) {
                let newTargets = draft.targets.filter { !goals[idx].targets.contains($0) }
                if !newTargets.isEmpty {
                    goals[idx].targets.append(contentsOf: newTargets)
                    save()
                }
            } else {
                let goal = ChatGoal(
                    title: draft.title,
                    targets: draft.targets,
                    keywords: draft.keywords,
                    timeline: draft.timeline
                )
                goals.append(goal)
                added.append(goal)
            }
        }

        if !added.isEmpty { save() }
        return added
    }

    // MARK: - 활동 트래킹 (캘린더 데이터 기반)

    func updateWeeklyActivity(events: [Any], completedIDs: Set<String>) {
        // events: CalendarEvent 배열을 Any로 받아 리플렉션 없이 처리
        // 실제 연결은 ReviewView에서 타입 안전하게 호출
    }

    /// CalendarEvent 배열로 주별 활동 업데이트
    func refreshActivity(
        calendarEvents: [(id: String, title: String, startDate: Date)],
        completedIDs: Set<String>
    ) {
        let cal = Calendar.current
        let now = Date()
        for i in 0..<goals.count {
            var weekly = [0, 0, 0, 0]
            for weekOffset in 0..<4 {
                let weekStart = cal.date(byAdding: .weekOfYear, value: -(3 - weekOffset), to: cal.startOfDay(for: now))!
                let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart)!
                let count = calendarEvents.filter { ev in
                    guard ev.startDate >= weekStart && ev.startDate < weekEnd else { return false }
                    return goals[i].keywords.contains { kw in
                        ev.title.localizedCaseInsensitiveContains(kw)
                    } || goals[i].targets.contains { t in
                        ev.title.localizedCaseInsensitiveContains(t)
                    }
                }.count
                weekly[weekOffset] = count
            }
            goals[i].weeklyActivity = weekly
            goals[i].lastActivityUpdate = now
        }
        save()
    }

    // MARK: - 진행률 계산

    func progressRate(for goal: ChatGoal,
                      events: [(id: String, title: String, startDate: Date)],
                      completedIDs: Set<String>) -> Double {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: Date()) else { return 0 }

        let relevant = events.filter { ev in
            guard ev.startDate >= interval.start && ev.startDate < interval.end else { return false }
            return goal.keywords.contains { kw in ev.title.localizedCaseInsensitiveContains(kw) }
                || goal.targets.contains { t in ev.title.localizedCaseInsensitiveContains(t) }
        }
        guard !relevant.isEmpty else { return 0 }
        let done = relevant.filter { completedIDs.contains($0.id) }.count
        return Double(done) / Double(relevant.count)
    }

    // 트렌드: 최근 2주 vs 이전 2주
    func trend(for goal: ChatGoal) -> GoalTrend {
        let w = goal.weeklyActivity
        let recent = w[2] + w[3]
        let older  = w[0] + w[1]
        if recent > older + 1 { return .rising }
        if recent < older - 1 { return .falling }
        return .steady
    }

    // MARK: - CRUD

    func update(_ goal: ChatGoal) {
        if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[idx] = goal
            save()
        }
    }

    func delete(_ goal: ChatGoal) {
        goals.removeAll { $0.id == goal.id }
        save()
    }

    func add(title: String, targets: [String], timeline: GoalTimeline) {
        let keywords = targets  // 타깃 자체를 키워드로
        let goal = ChatGoal(
            title: title, targets: targets, keywords: keywords,
            timeline: timeline
        )
        goals.append(goal)
        save()
    }

    // MARK: - 저장/로드

    private func save() {
        if let data = try? JSONEncoder().encode(goals) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ChatGoal].self, from: data) else { return }
        goals = decoded
        save()  // sourceMessage 등 구버전 필드 제거를 위해 즉시 재저장
    }
}

enum GoalTrend {
    case rising, steady, falling
    var icon: String {
        switch self { case .rising: return "arrow.up.right"; case .falling: return "arrow.down.right"; case .steady: return "arrow.right" }
    }
    var color: Color {
        switch self { case .rising: return .green; case .falling: return .red; case .steady: return .secondary }
    }
}
