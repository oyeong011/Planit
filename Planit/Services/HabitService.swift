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

    init(name: String, emoji: String, colorName: String, weeklyTarget: Int) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.colorName = colorName
        self.weeklyTarget = weeklyTarget
        self.createdAt = Date()
        self.completedDates = []
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
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() { load() }

    // MARK: - 완료 기록

    func toggleToday(_ habit: Habit) {
        guard let idx = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        let key = todayKey()
        if habits[idx].completedDates.contains(key) {
            habits[idx].completedDates.removeAll { $0 == key }
        } else {
            habits[idx].completedDates.append(key)
        }
        save()
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

    func add(name: String, emoji: String, colorName: String, weeklyTarget: Int) {
        let cleanName = sanitizeName(name)
        guard !cleanName.isEmpty else { return }
        // 중복 이름(대소문자·공백 무시) 방지
        guard !habits.contains(where: { $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { return }
        let safeColor  = Self.allowedColors.contains(colorName) ? colorName : "blue"
        let safeTarget = max(1, min(7, weeklyTarget))
        let safeEmoji  = sanitizeEmoji(emoji)
        let habit = Habit(name: cleanName, emoji: safeEmoji, colorName: safeColor, weeklyTarget: safeTarget)
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
        if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[idx] = updated
            save()
        }
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
