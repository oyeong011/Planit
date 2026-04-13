import Foundation

// MARK: - Review Mode

enum ReviewMode: String {
    case morning   // 아침 브리핑
    case evening   // 저녁 리뷰
    case none      // 일반 (채팅)
}

// MARK: - Review Service

@MainActor
final class ReviewService: ObservableObject {
    @Published var currentMode: ReviewMode = .none
    @Published var suggestions: [ReviewSuggestion] = []
    @Published var morningDoneToday: Bool = false
    @Published var eveningDoneToday: Bool = false
    @Published var tomorrowPlanResult: TomorrowPlanResult?

    private let goalService: GoalService
    private let calendarService: GoogleCalendarService?
    private var tomorrowPlanner: TomorrowPlannerService?

    init(goalService: GoalService, calendarService: GoogleCalendarService?) {
        self.goalService = goalService
        self.calendarService = calendarService
        self.tomorrowPlanner = TomorrowPlannerService(goalService: goalService, calendarService: calendarService)
    }

    // MARK: - Auto Mode Detection

    func checkAndActivate() {
        guard goalService.profile.onboardingDone else { return }

        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)

        let mStart = goalService.profile.morningBriefHour
        let eStart = goalService.profile.eveningReviewHour

        if hour >= mStart && hour < mStart + 2 && !morningDoneToday {
            if currentMode != .morning {
                currentMode = .morning
                Task { await generateMorningSuggestions() }
            }
        } else if hour >= eStart && hour < eStart + 3 && !eveningDoneToday {
            if currentMode != .evening {
                currentMode = .evening
                Task { await generateEveningSuggestions() }
            }
        }
        // Don't auto-switch to .none — let user manually go back to chat
    }

    /// Call this to finalize evening review and generate tomorrow plan.
    /// The plan is generated BEFORE dismiss so the UI can show the result.
    func finalizeEveningAndPlan() async {
        // Auto-record remaining unreviewed events as "moved"
        for suggestion in suggestions {
            let minutes = Int((suggestion.proposedEnd ?? Date()).timeIntervalSince(suggestion.proposedStart ?? Date()) / 60)
            goalService.markCompletion(
                eventId: suggestion.proposedTitle ?? suggestion.title,
                goalId: suggestion.goalId,
                status: .moved,
                plannedMinutes: max(minutes, 30)
            )
        }

        // Generate tomorrow plan while still in evening mode (UI visible)
        await generateTomorrowPlan()
    }

    func dismissReview() {
        if currentMode == .morning { morningDoneToday = true }
        if currentMode == .evening { eveningDoneToday = true }
        currentMode = .none
        suggestions = []
    }

    // MARK: - Tomorrow Planning

    func generateTomorrowPlan() async {
        guard let planner = tomorrowPlanner else { return }
        await planner.generateTomorrowPlan()
        tomorrowPlanResult = planner.lastResult
    }

    /// Inject auto-created + suggested items into morning briefing
    func injectTomorrowPlanIntoMorning() {
        guard let planner = tomorrowPlanner else { return }
        let planSuggestions = planner.suggestionsFromLastResult()
        if !planSuggestions.isEmpty {
            suggestions.insert(contentsOf: planSuggestions, at: 0)
        }
    }

    // MARK: - Morning Suggestions

    func generateMorningSuggestions() async {
        var items: [ReviewSuggestion] = []

        let activeGoals = goalService.activeGoals()
        let todayEvents = await fetchTodayEvents()
        let freeSlots = findFreeSlots(events: todayEvents)

        // 1. Carryover: yesterday's incomplete
        let yesterdayIncomplete = findYesterdayIncomplete()
        for (eventTitle, goalId) in yesterdayIncomplete.prefix(3) {
            if let slot = bestSlot(for: 60, from: freeSlots, goalId: goalId) {
                items.append(ReviewSuggestion(
                    type: .carryover,
                    title: "어제 '\(eventTitle)'을 놓쳤어요",
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

        // 3. Weekly habit gap
        for goal in activeGoals {
            guard let rec = goal.recurrence else { continue }
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

        // Cap at 5
        suggestions = Array(items.prefix(5))

        // Inject any auto-planned items from last night
        injectTomorrowPlanIntoMorning()
    }

    // MARK: - Evening Suggestions

    func generateEveningSuggestions() async {
        var items: [ReviewSuggestion] = []
        let todayEvents = await fetchTodayEvents()

        // Generate completion check cards for each event
        for event in todayEvents where !event.isAllDay {
            let hasRecord = goalService.completionFor(eventId: event.id) != nil
            if !hasRecord && event.endDate < Date() {
                items.append(ReviewSuggestion(
                    type: .carryover,
                    title: event.title,
                    description: "\(formatTime(event.startDate))~\(formatTime(event.endDate))",
                    goalId: nil,
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
        return (try? await service.fetchEvents(for: Date())) ?? []
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
            .map { ($0.eventId, $0.goalId) }  // eventId used as title fallback
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
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
        return fmt.string(from: date)
    }
}
