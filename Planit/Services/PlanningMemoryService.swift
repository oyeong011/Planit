import Foundation

// MARK: - PlanningMemoryService
// 목표/완료/습관 스냅샷에서 AI 프롬프트용 계획 메모리 요약을 생성한다.
// 순수 정적 함수 — 부작용 없음, 테스트 용이.

enum PlanningMemoryService {

    struct PlanningFeedbackSnapshot: Codable {
        var quickActionCounts: [String: Int] = [:]
        var acceptedActionCounts: [String: Int] = [:]
        var lastUpdatedAt: Date = Date()
    }

    private static let feedbackFileName = "planning_memory_feedback.json"

    // MARK: - Public

    static func buildSummary(
        goals: [Goal],
        completions: [String: CompletionRecord],
        dailyMetrics: [String: DailyMetrics],
        profile: UserProfile,
        habits: [Habit],
        events: [CalendarEvent] = [],
        todos: [TodoItem] = []
    ) -> String {
        let feedback = loadFeedbackSnapshot()
        return buildSummary(
            goals: goals,
            completions: completions,
            dailyMetrics: dailyMetrics,
            profile: profile,
            habits: habits,
            events: events,
            todos: todos,
            feedback: feedback
        )
    }

    static func buildSummary(
        goals: [Goal],
        completions: [String: CompletionRecord],
        dailyMetrics: [String: DailyMetrics],
        profile: UserProfile,
        habits: [Habit],
        events: [CalendarEvent] = [],
        todos: [TodoItem] = [],
        feedback: PlanningFeedbackSnapshot
    ) -> String {
        var lines: [String] = []

        lines.append(focusWindowLine(profile: profile))

        let tendency = weeklyTendency(dailyMetrics: dailyMetrics)
        lines.append("주간 완료율: \(Int(tendency.completionRate * 100))%")
        if tendency.moveFraction > 0.25 {
            lines.append("이동 경향: 높음 (\(Int(tendency.moveFraction * 100))%)")
        }
        if tendency.skipFraction > 0.20 {
            lines.append("건너뜀 경향: 높음 (\(Int(tendency.skipFraction * 100))%)")
        }

        let overload = overloadSignal(goals: goals, profile: profile)
        if !overload.isEmpty { lines.append(overload) }

        if let todayLoad = busiestUpcomingDayLine(events: events) {
            lines.append(todayLoad)
        }
        if let todoPressure = todoPressureLine(todos: todos) {
            lines.append(todoPressure)
        }

        lines.append(contentsOf: goalDeficitLines(goals: goals, completions: completions))
        lines.append(contentsOf: habitMomentumLines(habits: habits))
        lines.append(contentsOf: feedbackLines(snapshot: feedback))

        return """
        ## 📊 플래닝 메모리
        \(lines.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    static func recordQuickAction(label: String) {
        mutateFeedbackSnapshot { snapshot in
            snapshot.quickActionCounts[label, default: 0] += 1
        }
    }

    static func recordAcceptedActions(_ actions: [CalendarAction]) {
        guard !actions.isEmpty else { return }
        mutateFeedbackSnapshot { snapshot in
            for action in actions {
                snapshot.acceptedActionCounts[action.action, default: 0] += 1
            }
        }
    }

    // MARK: - Helpers (internal access for testing)

    static func focusWindowLine(profile: UserProfile) -> String {
        let start: Int
        let end: Int
        switch profile.energyType {
        case .morning:
            start = profile.workStartHour
            end = min(profile.workStartHour + 3, profile.lunchStartHour)
        case .evening:
            start = max(profile.workEndHour - 3, profile.lunchEndHour)
            end = profile.workEndHour
        case .balanced:
            start = max(profile.lunchEndHour, profile.workStartHour)
            end = start + 2
        }
        let fmt = { (h: Int) in String(format: "%02d:00", h) }
        return "집중 시간대: \(profile.energyType.rawValue) (\(fmt(start))~\(fmt(end)))"
    }

    struct WeeklyTendency {
        let completionRate: Double
        let moveFraction: Double
        let skipFraction: Double
    }

    static func weeklyTendency(dailyMetrics: [String: DailyMetrics]) -> WeeklyTendency {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: today) else {
            return WeeklyTendency(completionRate: 0, moveFraction: 0, skipFraction: 0)
        }
        let recent = dailyMetrics.values.filter { $0.date >= weekAgo }
        let totalPlanned = recent.reduce(0) { $0 + $1.plannedCount }
        guard totalPlanned > 0 else {
            return WeeklyTendency(completionRate: 0, moveFraction: 0, skipFraction: 0)
        }
        let done    = recent.reduce(0) { $0 + $1.completedCount }
        let moved   = recent.reduce(0) { $0 + $1.movedCount }
        let skipped = recent.reduce(0) { $0 + $1.skippedCount }
        return WeeklyTendency(
            completionRate: Double(done) / Double(totalPlanned),
            moveFraction:   Double(moved) / Double(totalPlanned),
            skipFraction:   Double(skipped) / Double(totalPlanned)
        )
    }

    static func overloadSignal(goals: [Goal], profile: UserProfile) -> String {
        let active = goals.filter { $0.status == .active }
        guard !active.isEmpty else { return "" }

        let targetMins = active.compactMap { $0.targetHours }.reduce(0.0) { $0 + $1 * 60 }
        let capacity = Double(profile.weekdayCapacityMinutes * 5 + profile.weekendCapacityMinutes * 2)

        if capacity > 0, targetMins > capacity * 0.8 {
            return "부하 신호: 과부하 (목표 \(active.count)개, 용량 \(Int((targetMins / capacity) * 100))%)"
        }
        if active.count >= 6 {
            return "부하 신호: 활성 목표 \(active.count)개"
        }
        return ""
    }

    static func busiestUpcomingDayLine(events: [CalendarEvent]) -> String? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: today) else { return nil }

        let grouped = Dictionary(grouping: events.filter {
            $0.startDate >= today && $0.startDate < weekEnd && !$0.isAllDay
        }) { event in
            cal.startOfDay(for: event.startDate)
        }

        guard let busiest = grouped.max(by: { $0.value.count < $1.value.count }), busiest.value.count >= 4 else {
            return nil
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "M/d(E)"
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
        return "다가오는 과밀일: \(fmt.string(from: busiest.key)) 일정 \(busiest.value.count)개"
    }

    static func todoPressureLine(todos: [TodoItem]) -> String? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: today) else { return nil }

        let active = todos.filter {
            !$0.isCompleted && $0.date >= today && $0.date < weekEnd
        }
        guard !active.isEmpty else { return nil }

        let todayTodos = active.filter { cal.isDate($0.date, inSameDayAs: today) }.count
        if todayTodos >= 4 {
            return "오늘 할 일 압박: 미완료 \(todayTodos)개"
        }
        if active.count >= 8 {
            return "주간 할 일 압박: 미완료 \(active.count)개"
        }
        return nil
    }

    static func feedbackLines(snapshot: PlanningFeedbackSnapshot) -> [String] {
        var lines: [String] = []
        if let favoriteQuickAction = snapshot.quickActionCounts.max(by: { $0.value < $1.value }), favoriteQuickAction.value >= 2 {
            lines.append("자주 쓰는 플래닝: \(favoriteQuickAction.key) (\(favoriteQuickAction.value)회)")
        }
        if let favoriteAcceptedAction = snapshot.acceptedActionCounts.max(by: { $0.value < $1.value }), favoriteAcceptedAction.value >= 2 {
            lines.append("자주 승인한 실행: \(favoriteAcceptedAction.key) (\(favoriteAcceptedAction.value)회)")
        }
        return lines
    }

    private static func mutateFeedbackSnapshot(_ mutate: (inout PlanningFeedbackSnapshot) -> Void) {
        var snapshot = loadFeedbackSnapshot()
        mutate(&snapshot)
        snapshot.lastUpdatedAt = Date()
        saveFeedbackSnapshot(snapshot)
    }

    private static func loadFeedbackSnapshot() -> PlanningFeedbackSnapshot {
        guard let data = try? Data(contentsOf: feedbackFileURL()) else {
            return PlanningFeedbackSnapshot()
        }
        return (try? JSONDecoder.planitDecoder.decode(PlanningFeedbackSnapshot.self, from: data)) ?? PlanningFeedbackSnapshot()
    }

    private static func saveFeedbackSnapshot(_ snapshot: PlanningFeedbackSnapshot) {
        let url = feedbackFileURL()
        guard let data = try? JSONEncoder.planitEncoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func feedbackFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Planit", isDirectory: true)
            .appendingPathComponent(feedbackFileName)
    }

    static func goalDeficitLines(goals: [Goal], completions: [String: CompletionRecord]) -> [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return []
        }
        return goals
            .filter { $0.status == .active && $0.recurrence != nil }
            .compactMap { goal -> String? in
                guard let rec = goal.recurrence else { return nil }
                let done = completions.values
                    .filter { $0.goalId == goal.id && $0.date >= weekStart && $0.status == .done }
                    .count
                let deficit = rec.weeklyTargetSessions - done
                guard deficit > 0 else { return nil }
                let short = goal.title.count > 8 ? String(goal.title.prefix(8)) + "…" : goal.title
                return "지연 목표: \(short) (-\(deficit)세션)"
            }
            .prefix(3)
            .map { $0 }
    }

    static func habitMomentumLines(habits: [Habit]) -> [String] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return []
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Asia/Seoul")

        return habits.prefix(5).compactMap { habit -> String? in
            let weekDone = (0..<7).filter { offset -> Bool in
                guard let d = cal.date(byAdding: .day, value: offset, to: weekStart) else { return false }
                return habit.completedDates.contains(fmt.string(from: d))
            }.count

            var streak = 0
            var cursor = today
            while true {
                if habit.completedDates.contains(fmt.string(from: cursor)) {
                    streak += 1
                    guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                    cursor = prev
                } else { break }
            }

            let short = habit.name.count > 6 ? String(habit.name.prefix(6)) + "…" : habit.name
            if streak >= 3 {
                return "습관 [\(short)]: 🔥\(streak)일 연속"
            } else if weekDone < habit.weeklyTarget {
                return "습관 [\(short)]: 주 \(weekDone)/\(habit.weeklyTarget)"
            }
            return nil
        }
    }
}
