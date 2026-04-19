import Foundation

// MARK: - Review Mode

enum ReviewMode: String {
    case daily     // 일일 조정 (항상 활성)
    case evening   // 저녁 리뷰 (과거 이벤트 완료 체크)
    case none      // 일반 (채팅)
}

// MARK: - Review Service

@MainActor
final class ReviewService: ObservableObject {
    @Published var currentMode: ReviewMode = .none
    @Published var suggestions: [ReviewSuggestion] = []
    @Published var dailyDoneToday: Bool = false
    @Published var eveningDoneToday: Bool = false
    @Published var tomorrowPlanResult: TomorrowPlanResult?

    private let goalService: GoalService
    private let calendarService: GoogleCalendarService?
    private var tomorrowPlanner: TomorrowPlannerService?
    private var reviewAI: ReviewAIService?
    private static let lastDailyKeyName = "calen.review.lastDailyKey"
    static let lastEveningKeyName = "calen.review.lastEveningKey"
    private static let dateKeyFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
        return fmt
    }()
    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
        return fmt
    }()

    /// Persisted date key to prevent re-running daily adjustment on same day
    private var lastDailyKey: String {
        get { UserDefaults.standard.string(forKey: Self.lastDailyKeyName) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastDailyKeyName) }
    }

    /// Persisted date key to prevent re-running evening review after restart.
    private var lastEveningKey: String {
        get { UserDefaults.standard.string(forKey: Self.lastEveningKeyName) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastEveningKeyName) }
    }

    init(goalService: GoalService, calendarService: GoogleCalendarService?) {
        self.goalService = goalService
        self.calendarService = calendarService
        self.tomorrowPlanner = TomorrowPlannerService(goalService: goalService, calendarService: calendarService)
        self.reviewAI = ReviewAIService(goalService: goalService, calendarService: calendarService)

        // Check if daily adjustment was already done today (persists across app restarts)
        let todayKey = Self.dateKey(for: Date())
        if lastDailyKey == todayKey {
            dailyDoneToday = true
        }
        if lastEveningKey == todayKey {
            eveningDoneToday = true
        }
    }

    private static func dateKey(for date: Date) -> String {
        dateKeyFormatter.string(from: date)
    }

    // MARK: - Always-On Daily Adjustment

    /// Called on every app launch / popover open.
    /// Runs daily adjustment regardless of time — the core loop.
    func checkAndActivate() {
        guard goalService.profile.onboardingDone else { return }

        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        let eStart = goalService.profile.eveningReviewHour

        // 1. Daily adjustment — runs once per day, any time
        if !dailyDoneToday {
            if currentMode != .daily {
                currentMode = .daily
                Task { [weak self] in await self?.generateDailySuggestions() }
            }
            return
        }

        // 2. Evening review — only if daily is already done
        if hour >= eStart && hour < eStart + 3 && !eveningDoneToday {
            if currentMode != .evening {
                currentMode = .evening
                Task { await generateEveningSuggestions() }
            }
        }
    }

    /// Finalize review: record unreviewed as "moved", optionally plan tomorrow
    func finalizeAndPlan() async {
        for suggestion in suggestions where suggestion.status == .pending {
            let minutes = Int((suggestion.proposedEnd ?? Date()).timeIntervalSince(suggestion.proposedStart ?? Date()) / 60)
            goalService.markCompletion(
                eventId: suggestion.sourceEventId ?? suggestion.title,
                eventTitle: suggestion.title,
                goalId: suggestion.goalId,
                status: .moved,
                plannedMinutes: max(minutes, 30)
            )
        }

        // Generate tomorrow plan in evening mode
        if currentMode == .evening {
            await generateTomorrowPlan()
        }
    }

    func dismissReview() {
        if currentMode == .daily {
            dailyDoneToday = true
            lastDailyKey = Self.dateKey(for: Date())
        }
        if currentMode == .evening {
            eveningDoneToday = true
            lastEveningKey = Self.dateKey(for: Date())
        }
        currentMode = .none
        suggestions = []
    }

    // MARK: - AI Tomorrow Planning

    /// Claude AI가 오늘 리뷰를 분석해 내일 계획을 생성합니다.
    /// Google Calendar 없이도 동작하며, AI 실패 시 규칙 기반 폴백.
    func generateAITomorrowPlan(
        reviewed: [(title: String, status: CompletionStatus, start: Date, end: Date)]
    ) async -> ReviewAIPlan {
        guard let ai = reviewAI else {
            return ReviewAIPlan(events: [], summary: "", error: "ReviewAIService 초기화 실패")
        }
        return await ai.generateTomorrowPlan(reviewed: reviewed)
    }

    // MARK: - Tomorrow Planning (rule-based, kept as fallback)

    func generateTomorrowPlan() async {
        guard let planner = tomorrowPlanner else { return }
        await planner.generateTomorrowPlan()
        tomorrowPlanResult = planner.lastResult
    }

    // MARK: - Daily Suggestions (Always-On Core Loop)

    /// Generates suggestions any time of day:
    /// 1. Carryover incomplete tasks from yesterday
    /// 2. Deadline-approaching goals
    /// 3. Weekly habit gaps
    /// 4. Capacity check — warns if today is overloaded
    func generateDailySuggestions() async {
        var items: [ReviewSuggestion] = []

        let activeGoals = goalService.activeGoals()
        let todayEvents = await fetchTodayEvents()
        let freeSlots = findFreeSlots(events: todayEvents)

        // Calculate today's total scheduled minutes for capacity check
        let scheduledMinutes = todayEvents
            .filter { !$0.isAllDay }
            .reduce(0) { $0 + Int($1.endDate.timeIntervalSince($1.startDate) / 60) }
        let cal = Calendar.current
        let isWeekend = cal.isDateInWeekend(Date())
        let capacityMinutes = isWeekend
            ? goalService.profile.weekendCapacityMinutes
            : goalService.profile.weekdayCapacityMinutes

        // 1. Carryover: yesterday's incomplete
        let yesterdayIncomplete = findYesterdayIncomplete()
        for (eventTitle, goalId) in yesterdayIncomplete.prefix(3) {
            if let slot = bestSlot(for: 60, from: freeSlots, goalId: goalId) {
                items.append(ReviewSuggestion(
                    type: .carryover,
                    title: "미완료: '\(eventTitle)'",
                    description: "오늘 \(formatTime(slot.0))에 다시 잡을까요?",
                    goalId: goalId,
                    proposedStart: slot.0,
                    proposedEnd: slot.1,
                    proposedTitle: eventTitle
                ))
            }
        }

        // 2. Deadline proximity
        for goal in activeGoals {
            let daysLeft = goalService.daysUntilDeadline(goal)
            if daysLeft > 0 && daysLeft <= 7 {
                let sessionMin = goal.recurrence?.perSessionMinutes ?? goal.minSessionMinutes
                if !todayHasGoalBlock(goal.id, events: todayEvents) {
                    if let slot = bestSlot(for: sessionMin, from: freeSlots, goalId: goal.id) {
                        items.append(ReviewSuggestion(
                            type: .deadline,
                            title: "\(goal.title) D-\(daysLeft)",
                            description: "\(sessionMin)분 블록을 \(formatTime(slot.0))에 넣을까요?",
                            goalId: goal.id,
                            proposedStart: slot.0,
                            proposedEnd: slot.1,
                            proposedTitle: goal.title
                        ))
                    }
                }
            }
        }

        // 3. Weekly habit gap — 주간 반복 추적 알림
        // 단, 장기 goal(deadline 30일+ 또는 .year/.decade 레벨)은 제외.
        // 이유: "대학원입학" 같은 장기 목표에 매일 "20시에 60분" 제안이 뜨면 부적절.
        // 반복 활동은 별도 '습관' 기능으로 추적.
        for goal in activeGoals {
            guard let rec = goal.recurrence else { continue }
            let daysUntil = goalService.daysUntilDeadline(goal)
            let isLongTerm = goal.level == .year || daysUntil > 30
            if isLongTerm { continue }

            let thisWeekSessions = countThisWeekSessions(goalId: goal.id)
            if thisWeekSessions < rec.weeklyTargetSessions {
                let remaining = rec.weeklyTargetSessions - thisWeekSessions
                if !todayHasGoalBlock(goal.id, events: todayEvents) {
                    if let slot = bestSlot(for: rec.perSessionMinutes, from: freeSlots, goalId: goal.id) {
                        items.append(ReviewSuggestion(
                            type: .habitGap,
                            title: "\(goal.title) 이번주 \(thisWeekSessions)/\(rec.weeklyTargetSessions)회",
                            description: "\(remaining)회 남음. \(formatTime(slot.0))에 \(rec.perSessionMinutes)분?",
                            goalId: goal.id,
                            proposedStart: slot.0,
                            proposedEnd: slot.1,
                            proposedTitle: goal.title
                        ))
                    }
                }
            }
        }

        // 4. Capacity warning — if today is overloaded
        if scheduledMinutes > capacityMinutes && capacityMinutes > 0 {
            let overMinutes = scheduledMinutes - capacityMinutes
            items.insert(ReviewSuggestion(
                type: .focusQuota,
                title: "오늘 일정 초과 (+\(overMinutes)분)",
                description: "용량 \(capacityMinutes)분 대비 \(scheduledMinutes)분 예정. 조정이 필요해요.",
                goalId: nil
            ), at: 0)
        }

        // Cap at 7
        suggestions = Array(items.prefix(7))

        // Inject any auto-planned items from last night's tomorrow plan
        if let planner = tomorrowPlanner {
            let planSuggestions = planner.suggestionsFromLastResult()
            if !planSuggestions.isEmpty {
                suggestions.insert(contentsOf: planSuggestions, at: 0)
            }
        }
    }

    // MARK: - Evening Suggestions (Completion Check)

    func generateEveningSuggestions() async {
        var items: [ReviewSuggestion] = []
        let todayEvents = await fetchTodayEvents()

        var seenIds = Set<String>()

        for event in todayEvents where !event.isAllDay {
            guard !seenIds.contains(event.id) else { continue }
            seenIds.insert(event.id)

            let hasRecord = goalService.completionFor(eventId: event.id) != nil
            if !hasRecord && event.endDate < Date() {
                items.append(ReviewSuggestion(
                    type: .carryover,
                    title: event.title,
                    description: "\(formatTime(event.startDate))~\(formatTime(event.endDate))",
                    goalId: nil,
                    sourceEventId: event.id,
                    proposedStart: event.startDate,
                    proposedEnd: event.endDate,
                    proposedTitle: event.title
                ))
            }
        }

        suggestions = items
    }

    // MARK: - Scoring & Slot Finding

    private func findFreeSlots(events: [CalendarEvent]) -> [(Date, Date)] {
        let cal = Calendar.current
        let profile = goalService.profile
        let today = cal.startOfDay(for: Date())

        // Work hours
        let dayStart = cal.date(bySettingHour: profile.workStartHour - 1, minute: 0, second: 0, of: today)!
        let dayEnd = cal.date(bySettingHour: profile.workEndHour + 2, minute: 0, second: 0, of: today)!

        // Sort busy blocks
        let busy = events
            .filter { !$0.isAllDay }
            .map { (max($0.startDate, dayStart), min($0.endDate, dayEnd)) }
            .sorted { $0.0 < $1.0 }

        // Skip lunch
        let lunchStart = cal.date(bySettingHour: profile.lunchStartHour, minute: 0, second: 0, of: today)!
        let lunchEnd = cal.date(bySettingHour: profile.lunchEndHour, minute: 0, second: 0, of: today)!

        var allBusy = busy + [(lunchStart, lunchEnd)]
        allBusy.sort { $0.0 < $1.0 }

        // Find gaps ≥ 25 min
        var slots: [(Date, Date)] = []
        var cursor = max(dayStart, Date().addingTimeInterval(600))  // Start from now + 10min

        for (busyStart, busyEnd) in allBusy {
            if cursor < busyStart {
                let gap = busyStart.timeIntervalSince(cursor)
                if gap >= 25 * 60 {
                    slots.append((cursor, busyStart))
                }
            }
            cursor = max(cursor, busyEnd)
        }
        if cursor < dayEnd {
            let gap = dayEnd.timeIntervalSince(cursor)
            if gap >= 25 * 60 {
                slots.append((cursor, dayEnd))
            }
        }

        return slots
    }

    private func bestSlot(for minutes: Int, from slots: [(Date, Date)], goalId: String?) -> (Date, Date)? {
        let duration = TimeInterval(minutes * 60)
        // Find first slot that fits
        for (start, end) in slots {
            if end.timeIntervalSince(start) >= duration {
                return (start, start.addingTimeInterval(duration))
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func fetchTodayEvents() async -> [CalendarEvent] {
        guard let service = calendarService else { return [] }
        let allEvents = (try? await service.fetchEvents(for: Date())) ?? []
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart)!
        return allEvents.filter { $0.startDate >= todayStart && $0.startDate < tomorrowStart }
    }

    private func todayHasGoalBlock(_ goalId: String, events: [CalendarEvent]) -> Bool {
        // Check if any of today's events are linked to this goal
        // For now, match by title prefix
        let goal = goalService.goals.first { $0.id == goalId }
        guard let goalTitle = goal?.title else { return false }
        return events.contains { $0.title.contains(goalTitle) }
    }

    private func findYesterdayIncomplete() -> [(String, String?)] {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        let today = cal.startOfDay(for: Date())

        return goalService.completions.values
            .filter { $0.date >= yesterday && $0.date < today && $0.status != .done }
            .compactMap { record -> (String, String?)? in
                guard let title = record.eventTitle else { return nil }
                return (title, record.goalId)
            }  // eventTitle 없는 레코드 제외 (eventId가 제목으로 노출되는 것 방지)
    }

    private func countThisWeekSessions(goalId: String) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!

        return goalService.completions.values
            .filter { $0.goalId == goalId && $0.date >= weekStart && $0.status == .done }
            .count
    }

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
