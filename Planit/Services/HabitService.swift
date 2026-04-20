import Foundation
import SwiftUI
import os

// MARK: - Models

struct Habit: Codable, Identifiable {
    let id: UUID
    var name: String           // "운동", "일찍 일어나기"
    var emoji: String          // "🏋️", "🌅"
    var colorName: String      // SwiftUI named color key
    var weeklyTarget: Int      // 주 N회 목표 (1–7)
    var createdAt: Date
    var completedDates: [String]  // "yyyy-MM-dd" 형식
    // 기간 한정 습관 (v0.4.9): 두 필드가 모두 있으면 "범위 습관"으로 간주.
    // 달력 블럭 + 진행률 게이지 렌더링은 이 값이 있을 때만 활성화.
    var startDateKey: String?  // "yyyy-MM-dd"
    var endDateKey: String?    // "yyyy-MM-dd" (inclusive)

    init(name: String, emoji: String, colorName: String, weeklyTarget: Int,
         startDateKey: String? = nil, endDateKey: String? = nil) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.colorName = colorName
        self.weeklyTarget = weeklyTarget
        self.createdAt = Date()
        self.completedDates = []
        self.startDateKey = startDateKey
        self.endDateKey = endDateKey
    }

    /// 범위 습관 여부 (start/end 둘 다 있고 start ≤ end)
    var isRanged: Bool {
        guard let s = startDateKey, let e = endDateKey else { return false }
        return s <= e  // "yyyy-MM-dd" 문자열은 사전순이 시간순과 일치
    }

    var accentColor: Color {
        switch colorName {
        case "blue":   return Color(hue: 0.58, saturation: 0.7, brightness: 0.85)
        case "green":  return Color(hue: 0.38, saturation: 0.65, brightness: 0.72)
        case "orange": return Color(hue: 0.08, saturation: 0.75, brightness: 0.90)
        case "purple": return Color(hue: 0.72, saturation: 0.60, brightness: 0.80)
        case "red":    return Color(hue: 0.00, saturation: 0.65, brightness: 0.82)
        case "teal":   return Color(hue: 0.50, saturation: 0.60, brightness: 0.75)
        default:       return Color(hue: 0.58, saturation: 0.7, brightness: 0.85)
        }
    }
}

// MARK: - HabitService

@MainActor
final class HabitService: ObservableObject {

    @Published private(set) var habits: [Habit] = []

    private let storageKey = "planit.habits.v1"
    private let logger = Logger(subsystem: "com.planit.calen", category: "HabitService")
    // 저장용 날짜 키는 반드시 Gregorian + POSIX — 사용자 Locale이 태국 불력/일본 황력이어도
    // "yyyy-MM-dd" 그레고리안 기준으로 일관 생성/파싱되어야 사전순 비교가 안전.
    // autoupdatingCurrent: 메뉴바 앱은 장시간 실행되므로 해외 이동 시 기기 타임존 변경을 바로 반영.
    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar   = Calendar(identifier: .gregorian)
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = TimeZone.autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private var dateFormatter: DateFormatter { Self.dayKeyFormatter }

    init() { load() }

    // MARK: - 완료 기록

    func toggleToday(_ habit: Habit) {
        toggle(habit, on: Date())
    }

    /// 임의 날짜 체크 토글. 범위 습관이면 범위 밖 날짜는 무시.
    func toggle(_ habit: Habit, on date: Date) {
        guard let idx = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        // 범위 습관: 범위 밖 토글 차단 (예방적)
        if habits[idx].isRanged && !isInRange(habits[idx], on: date) { return }
        let key = dateFormatter.string(from: date)
        if habits[idx].completedDates.contains(key) {
            habits[idx].completedDates.removeAll { $0 == key }
        } else {
            habits[idx].completedDates.append(key)
        }
        save()
    }

    /// 7일(또는 그 이하) 배열과 겹치는 범위 습관 리스트.
    /// 정렬: 시작일 이른 순 → 같으면 이름 오름차순.
    func rangedHabits(activeIn days: [Date]) -> [Habit] {
        guard !days.isEmpty else { return [] }
        let cal = Calendar.current
        let keys = days.map { dateFormatter.string(from: cal.startOfDay(for: $0)) }
        guard let minKey = keys.min(), let maxKey = keys.max() else { return [] }
        return habits.filter { habit in
            guard habit.isRanged,
                  let s = habit.startDateKey,
                  let e = habit.endDateKey else { return false }
            // 두 범위 [s,e] ↔ [minKey,maxKey] 교집합 있는지 (inclusive)
            return s <= maxKey && e >= minKey
        }.sorted { lhs, rhs in
            if let ls = lhs.startDateKey, let rs = rhs.startDateKey, ls != rs {
                return ls < rs
            }
            return lhs.name < rhs.name
        }
    }

    func isCompletedToday(_ habit: Habit) -> Bool {
        habit.completedDates.contains(todayKey())
    }

    func isCompleted(_ habit: Habit, on date: Date) -> Bool {
        habit.completedDates.contains(dateFormatter.string(from: date))
    }

    /// 최근 N일 완료 날짜 배열 (true/false)
    func completions(_ habit: Habit, days: Int = 7) -> [Bool] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).map { offset in
            let day = cal.date(byAdding: .day, value: -(days - 1 - offset), to: today)!
            return isCompleted(habit, on: day)
        }
    }

    /// 현재 연속 달성일 (streak)
    func streak(for habit: Habit) -> Int {
        let cal = Calendar.current
        var count = 0
        var day = cal.startOfDay(for: Date())
        while true {
            if isCompleted(habit, on: day) {
                count += 1
                day = cal.date(byAdding: .day, value: -1, to: day)!
            } else {
                break
            }
        }
        return count
    }

    /// 이번 주 완료 횟수
    func thisWeekCount(for habit: Habit) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).filter { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            return isCompleted(habit, on: day)
        }.count
    }

    // MARK: - 범위 습관 (v0.4.9 +)

    /// 해당 날짜가 습관의 활성 범위 내인지 (범위 없으면 항상 true)
    func isInRange(_ habit: Habit, on date: Date) -> Bool {
        guard habit.isRanged,
              let startKey = habit.startDateKey,
              let endKey = habit.endDateKey else { return true }
        let key = dateFormatter.string(from: date)
        return key >= startKey && key <= endKey
    }

    /// 범위 습관 진행률: (완료일수, 총일수, 0~1 비율).
    /// 범위가 아닌 습관엔 (0,0,0) 반환.
    func rangeProgress(_ habit: Habit) -> (completed: Int, total: Int, ratio: Double) {
        guard habit.isRanged,
              let startKey = habit.startDateKey,
              let endKey = habit.endDateKey,
              let startDate = dateFormatter.date(from: startKey),
              let endDate = dateFormatter.date(from: endKey) else {
            return (0, 0, 0)
        }
        let cal = Calendar.current
        let s = cal.startOfDay(for: startDate)
        let e = cal.startOfDay(for: endDate)
        let totalDays = (cal.dateComponents([.day], from: s, to: e).day ?? 0) + 1
        guard totalDays > 0 else { return (0, 0, 0) }
        // completedDates 중 범위 내 항목만 카운트 (중복/범위 밖 제거)
        var seen = Set<String>()
        for key in habit.completedDates where key >= startKey && key <= endKey {
            seen.insert(key)
        }
        let done = seen.count
        return (done, totalDays, Double(done) / Double(totalDays))
    }

    // MARK: - AI 채팅 습관 감지 (목표와 완전히 분리)

    private let habitDetector = LocalHabitDetector()

    /// 사용자 채팅 메시지에서 습관 의도 감지 후 자동 저장. 새로 추가된 습관 배열 반환
    @discardableResult
    func processUserMessage(_ message: String) -> [Habit] {
        let drafts = habitDetector.detect(in: message)
        var added: [Habit] = []
        for draft in drafts {
            // 대소문자·발음부호 무시한 중복 체크 (add()와 동일한 기준)
            let isDuplicate = habits.contains {
                $0.name.compare(draft.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            if isDuplicate { continue }
            let habit = Habit(name: draft.name, emoji: draft.emoji,
                              colorName: draft.colorName, weeklyTarget: draft.weeklyTarget)
            habits.append(habit)
            added.append(habit)
        }
        if !added.isEmpty { save() }
        return added
    }

    // MARK: - 입력 정규화 (서비스 계층 검증)

    private static let allowedColors: Set<String> = ["blue","green","orange","purple","red","teal"]
    private static let maxNameLength = 30

    /// 이름 정규화: 앞뒤 공백/개행 제거, 최대 30자, 제어문자 제거
    private func sanitizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let noControl = trimmed.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(noControl))
        return String(result.prefix(Self.maxNameLength))
    }

    /// 이모지: 첫 번째 grapheme cluster(문자)만 허용
    private func sanitizeEmoji(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "⭐" }
        return String(first)  // grapheme cluster 단위 첫 글자
    }

    // MARK: - CRUD

    func add(name: String, emoji: String, colorName: String, weeklyTarget: Int,
             startDate: Date? = nil, endDate: Date? = nil) {
        let cleanName = sanitizeName(name)
        guard !cleanName.isEmpty else { return }
        // 중복 이름(대소문자·공백 무시) 방지
        guard !habits.contains(where: { $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { return }
        let safeColor  = Self.allowedColors.contains(colorName) ? colorName : "blue"
        let safeTarget = max(1, min(7, weeklyTarget))
        let safeEmoji  = sanitizeEmoji(emoji)
        let (sKey, eKey) = Self.normalizeRange(start: startDate, end: endDate, formatter: dateFormatter)
        let habit = Habit(name: cleanName, emoji: safeEmoji, colorName: safeColor,
                          weeklyTarget: safeTarget, startDateKey: sKey, endDateKey: eKey)
        habits.append(habit)
        save()
    }

    func update(_ habit: Habit) {
        guard var updated = habits.first(where: { $0.id == habit.id }) else { return }
        let cleanName = sanitizeName(habit.name)
        guard !cleanName.isEmpty else { return }
        // 다른 습관과 이름 충돌 방지 (자기 자신 제외)
        let isDuplicate = habits.contains {
            $0.id != habit.id &&
            $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !isDuplicate else { return }
        updated.name         = cleanName
        updated.emoji        = sanitizeEmoji(habit.emoji)
        updated.colorName    = Self.allowedColors.contains(habit.colorName) ? habit.colorName : "blue"
        updated.weeklyTarget = max(1, min(7, habit.weeklyTarget))
        // 범위 필드 정규화 (start > end 면 swap, 한 쪽만 있으면 무효화)
        let sDate = habit.startDateKey.flatMap { dateFormatter.date(from: $0) }
        let eDate = habit.endDateKey.flatMap { dateFormatter.date(from: $0) }
        let (sKey, eKey) = Self.normalizeRange(start: sDate, end: eDate, formatter: dateFormatter)
        updated.startDateKey = sKey
        updated.endDateKey   = eKey
        if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[idx] = updated
            save()
        }
    }

    /// start/end 둘 다 있을 때만 유효 범위로 저장. start > end 면 swap.
    private static func normalizeRange(start: Date?, end: Date?, formatter: DateFormatter) -> (String?, String?) {
        guard let s0 = start, let e0 = end else { return (nil, nil) }
        let cal = Calendar.current
        let sDay = cal.startOfDay(for: s0)
        let eDay = cal.startOfDay(for: e0)
        let (lo, hi) = sDay <= eDay ? (sDay, eDay) : (eDay, sDay)
        return (formatter.string(from: lo), formatter.string(from: hi))
    }

    func delete(_ habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        save()
    }

    // MARK: - 저장/로드

    private func todayKey() -> String {
        dateFormatter.string(from: Date())
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(habits)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logger.error("HabitService save failed: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([Habit].self, from: data)
            // 구버전 데이터 마이그레이션: 잘못된 필드 정규화 후 재저장
            var needsSave = false
            habits = decoded.map { h in
                var m = h
                let clean = sanitizeName(h.name)
                if clean != h.name              { m.name        = clean;   needsSave = true }
                if m.name.isEmpty               { m.name        = "습관";   needsSave = true }
                let safeEmoji = sanitizeEmoji(h.emoji)
                if safeEmoji != h.emoji         { m.emoji       = safeEmoji; needsSave = true }
                if !Self.allowedColors.contains(h.colorName) { m.colorName = "blue"; needsSave = true }
                let clamped = max(1, min(7, h.weeklyTarget))
                if clamped != h.weeklyTarget    { m.weeklyTarget = clamped; needsSave = true }
                return m
            }
            if needsSave { save() }
        } catch {
            logger.error("HabitService load failed: \(error)")
        }
    }
}

// MARK: - Preset Habits (빠른 추가용)

struct HabitPreset {
    let name: String
    let emoji: String
    let colorName: String

    static let all: [HabitPreset] = [
        HabitPreset(name: NSLocalizedString("habit.preset.exercise", comment: ""), emoji: "🏋️", colorName: "orange"),
        HabitPreset(name: NSLocalizedString("habit.preset.wake", comment: ""),     emoji: "🌅", colorName: "teal"),
        HabitPreset(name: NSLocalizedString("habit.preset.reading", comment: ""),  emoji: "📚", colorName: "blue"),
        HabitPreset(name: NSLocalizedString("habit.preset.meditation", comment: ""), emoji: "🧘", colorName: "purple"),
        HabitPreset(name: NSLocalizedString("habit.preset.water", comment: ""),    emoji: "💧", colorName: "teal"),
        HabitPreset(name: NSLocalizedString("habit.preset.study", comment: ""),    emoji: "📖", colorName: "green"),
        HabitPreset(name: NSLocalizedString("habit.preset.sleep", comment: ""),    emoji: "😴", colorName: "purple"),
        HabitPreset(name: NSLocalizedString("habit.preset.diet", comment: ""),     emoji: "🥗", colorName: "green"),
    ]
}

// MARK: - Local Habit Detector (AI 채팅 메시지에서 습관 의도 감지)

struct HabitDraft {
    var name: String
    var emoji: String
    var colorName: String
    var weeklyTarget: Int
}

/// API 없이 로컬 키워드로 습관 의도를 감지.
///
/// 감지 전략: 트리거(반복 의도) + 도메인 키워드(습관 종류) 두 조건 AND
/// - 트리거: "매일", "루틴", "꾸준히" 등 반복 문맥 → 이 단어 없으면 즉시 무시
/// - 도메인: "운동", "헬스", "독서" 등 단순 키워드 → 트리거 있을 때만 검사
/// → "매일 헬스하고 싶어" ✓ / "헬스 목표야" ✗ (목표 detector가 처리)
// struct → 저장 프로퍼티가 불변이므로 Sendable 자동 준수
struct LocalHabitDetector: Sendable {

    // 습관 전용 반복 의도 트리거 (목표 트리거 "목표", "되고싶어", "합격" 등과 교집합 없음)
    private let habitTriggers = [
        "매일", "하루에", "매주", "주에", "습관", "루틴", "꾸준히",
        "챙겨야", "규칙적으로", "아침마다", "저녁마다", "날마다",
        "습관으로", "루틴으로", "습관화", "매일매일", "하루도 빠짐없이"
    ]

    // 도메인 키워드: 트리거가 있을 때만 검사. 단순 키워드로 자연스러운 표현 포괄
    private let patterns: [(name: String, emoji: String, color: String, keywords: [String], weekly: Int)] = [
        ("운동",         "🏋️", "orange", ["운동", "헬스", "gym", "피트니스", "웨이트", "근력운동"], 3),
        ("러닝",         "🏃", "orange", ["러닝", "달리기", "조깅", "jogging", "뛰기"],            3),
        ("일찍 일어나기", "🌅", "teal",   ["일찍 일어나", "기상", "미라클모닝", "아침형"],           5),
        ("독서",         "📚", "blue",   ["독서", "책읽기", "책을 읽", "책 읽"],                   5),
        ("명상",         "🧘", "purple", ["명상", "마음챙김", "호흡"],                             5),
        ("물 마시기",    "💧", "teal",   ["물마시기", "물 마시", "수분", "물을 마"],                7),
        ("공부",         "📖", "green",  ["공부", "학습", "스터디"],                               5),
        ("일기 쓰기",    "✍️", "blue",   ["일기", "다이어리", "저널링"],                            5),
        ("스트레칭",     "🌿", "green",  ["스트레칭", "유연성", "요가"],                            5),
        ("영어 공부",    "📖", "blue",   ["영어 공부", "영단어", "영어 회화", "영어 듣기"],          5),
        ("식단 관리",    "🥗", "green",  ["식단", "다이어트", "채식", "야채", "칼로리"],             5),
        ("일찍 자기",    "😴", "purple", ["일찍 자", "수면", "취침"],                              7),
    ]

    func detect(in message: String) -> [HabitDraft] {
        // 1차: 반복 의도 트리거 존재 여부 (없으면 조기 리턴 — 목표 detector와 경계 분리)
        let hasIntent = habitTriggers.contains { message.localizedCaseInsensitiveContains($0) }
        guard hasIntent else { return [] }

        // 2차: 트리거가 있는 상태에서 도메인 키워드 매칭
        var drafts: [HabitDraft] = []
        for p in patterns {
            let matched = p.keywords.contains { message.localizedCaseInsensitiveContains($0) }
            if matched {
                drafts.append(HabitDraft(name: p.name, emoji: p.emoji,
                                         colorName: p.color, weeklyTarget: p.weekly))
            }
        }
        return drafts
    }
}
