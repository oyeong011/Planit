import CalenShared
import Foundation

// MARK: - Planned Item

struct PlannedItem: Identifiable {
    let id = UUID().uuidString
    let goalId: String?
    let title: String
    let duration: Int          // minutes
    let score: Double
    let type: SuggestionType
    let preferredTimeTags: [String]

    // Assigned after scheduling
    var assignedStart: Date?
    var assignedEnd: Date?
    var calendarEventId: String?
    var autoCreated: Bool = false
}

// MARK: - Plan Result

struct TomorrowPlanResult {
    var created: [PlannedItem]      // auto-created in Google Calendar
    var suggested: [PlannedItem]    // shown as suggestions in morning briefing
    var totalMinutesPlanned: Int
    var capacityMinutes: Int
    var error: String?
}

// MARK: - Tomorrow Planner Service

@MainActor
protocol TomorrowPlannerGoalProviding: AnyObject {
    var profile: UserProfile { get }
    var goals: [Goal] { get }
    var completions: [String: CompletionRecord] { get }
    func activeGoals() -> [Goal]
    func daysUntilDeadline(_ goal: Goal) -> Int
}

@MainActor
protocol TomorrowPlannerCalendarServicing: AnyObject {
    func fetchEvents(for month: Date) async throws -> [CalendarEvent]
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        recurrence: String?
    ) async throws -> CalendarEvent?
}

extension GoalService: TomorrowPlannerGoalProviding {
    func activeGoals() -> [Goal] {
        activeGoals(level: nil)
    }
}
extension GoogleCalendarService: TomorrowPlannerCalendarServicing {}

@MainActor
final class TomorrowPlannerService: ObservableObject {
    @Published var lastResult: TomorrowPlanResult?
    @Published var isPlanning: Bool = false

    /// Persisted date key to prevent duplicate planning across app restarts
    private var lastPlannedDateKey: String {
        get { defaults.string(forKey: "planit.lastPlannedDate") ?? "" }
        set { defaults.set(newValue, forKey: "planit.lastPlannedDate") }
    }

    private let goalService: any TomorrowPlannerGoalProviding
    private let calendarService: (any TomorrowPlannerCalendarServicing)?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let candidateCollector: ((Date) -> [PlannedItem])?

    init(goalService: GoalService, calendarService: GoogleCalendarService?) {
        self.goalService = goalService
        self.calendarService = calendarService
        self.defaults = .standard
        self.now = Date.init
        self.candidateCollector = nil
    }

    init(
        goalProvider: any TomorrowPlannerGoalProviding,
        calendarService: (any TomorrowPlannerCalendarServicing)?,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        candidateCollector: ((Date) -> [PlannedItem])? = nil
    ) {
        self.goalService = goalProvider
        self.calendarService = calendarService
        self.defaults = defaults
        self.now = now
        self.candidateCollector = candidateCollector
    }

    // MARK: - Main Entry Point

    func generateTomorrowPlan() async {
        // Idempotency: check date-scoped persistent flag
        let cal = Calendar.current
        let currentDate = now()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: currentDate))!
        let tomorrowKey = GoalService.dateKey(tomorrow)

        guard lastPlannedDateKey != tomorrowKey else { return }
        guard !isPlanning else { return }
        guard let calendarService else { return }

        isPlanning = true
        defer { isPlanning = false }

        let profile = goalService.profile
        let isWeekend = cal.isDateInWeekend(tomorrow)
        let capacityMinutes = isWeekend ? profile.weekendCapacityMinutes : profile.weekdayCapacityMinutes

        // 1. Collect candidates
        var candidates = candidateCollector?(tomorrow) ?? collectCandidates(for: tomorrow)
        guard !candidates.isEmpty else {
            lastResult = TomorrowPlanResult(created: [], suggested: [], totalMinutesPlanned: 0, capacityMinutes: capacityMinutes)
            lastPlannedDateKey = tomorrowKey
            return
        }

        // 2. Score and sort
        candidates.sort { $0.score > $1.score }

        // 3. Fetch tomorrow's existing events → free slots (propagate errors)
        let tomorrowEvents: [CalendarEvent]
        do {
            tomorrowEvents = try await calendarService.fetchEvents(for: tomorrow)
        } catch {
            // Don't mark as done — allow retry
            lastResult = TomorrowPlanResult(created: [], suggested: [], totalMinutesPlanned: 0,
                                            capacityMinutes: capacityMinutes, error: "캘린더 조회 실패: \(error.localizedDescription)")
            return
        }

        // Check for all-day busy events (holidays, PTO)
        let hasAllDayBusy = tomorrowEvents.contains { $0.isAllDay }
        if hasAllDayBusy {
            // Still schedule but reduce capacity by half as conservative measure
            // (full block would need user confirmation)
        }

        let freeSlots = findFreeSlots(events: tomorrowEvents, on: tomorrow, profile: profile)

        guard !freeSlots.isEmpty else {
            lastResult = TomorrowPlanResult(created: [], suggested: [], totalMinutesPlanned: 0, capacityMinutes: capacityMinutes)
            lastPlannedDateKey = tomorrowKey
            return
        }

        // 4. Assign slots respecting capacity
        var usedMinutes = 0
        var scheduled: [PlannedItem] = []
        var remainingSlots = freeSlots

        for var item in candidates {
            guard usedMinutes + item.duration <= capacityMinutes else { break }

            if let slot = assignSlot(
                for: item,
                from: remainingSlots,
                energyType: profile.energyType,
                useFocusWindows: profile.usesFocusWindowsForAI
            ) {
                item.assignedStart = slot.start
                item.assignedEnd = slot.end
                scheduled.append(item)
                usedMinutes += item.duration
                remainingSlots = consumeSlot(slot, from: remainingSlots)
            }
        }

        // 5. Split into auto-created vs suggestions based on aggressiveness
        var created: [PlannedItem] = []
        var suggested: [PlannedItem] = []
        var hadCreateError = false
        var deniedCount = 0
        var confirmationCount = 0

        for var item in scheduled {
            let shouldAutoCreate: Bool
            switch profile.aggressiveness {
            case .auto:
                shouldAutoCreate = true
            case .semiAuto:
                shouldAutoCreate = created.count < 2
            case .assist:
                shouldAutoCreate = item.duration <= 30
            case .manual:
                shouldAutoCreate = false
            }

            if shouldAutoCreate, let start = item.assignedStart, let end = item.assignedEnd {
                let decision = ScheduleCreatePolicy.classify(
                    ScheduleCreateRequest(
                        title: item.title,
                        allowedCreateSources: allowedCreateSources(for: item),
                        isConfirmed: false
                    )
                )

                switch decision {
                case .allowed:
                    break
                case .needsConfirmation:
                    suggested.append(item)
                    confirmationCount += 1
                    continue
                case .denied:
                    suggested.append(item)
                    deniedCount += 1
                    continue
                }

                do {
                    let event = try await calendarService.createEvent(
                        title: item.title,
                        startDate: start,
                        endDate: end,
                        isAllDay: false,
                        recurrence: nil
                    )
                    if let event {
                        item.calendarEventId = event.id
                        item.autoCreated = true
                        created.append(item)
                    } else {
                        suggested.append(item)
                        hadCreateError = true
                    }
                } catch {
                    // API failed → fallback to suggestion
                    suggested.append(item)
                    hadCreateError = true
                }
            } else {
                suggested.append(item)
            }
        }

        lastResult = TomorrowPlanResult(
            created: created,
            suggested: suggested,
            totalMinutesPlanned: usedMinutes,
            capacityMinutes: capacityMinutes,
            error: buildResultSummary(
                deniedCount: deniedCount,
                confirmationCount: confirmationCount,
                hadCreateError: hadCreateError
            )
        )

        // Only mark as done if no fetch error (create errors are acceptable — items fall back to suggestions)
        lastPlannedDateKey = tomorrowKey
    }

    // MARK: - Candidate Collection

    private func collectCandidates(for tomorrow: Date) -> [PlannedItem] {
        var items: [PlannedItem] = []
        let cal = Calendar.current
        let tomorrowWeekday = cal.component(.weekday, from: tomorrow)  // 1=Sun, 7=Sat
        let isoWeekday = tomorrowWeekday == 1 ? 7 : tomorrowWeekday - 1
        let seenGoalIds = NSMutableSet()

        // A. Carryover: today's incomplete tasks (from CompletionRecords)
        let today = cal.startOfDay(for: now())
        let todayEnd = cal.date(byAdding: .day, value: 1, to: today)!

        let todayRecords = goalService.completions.values.filter {
            $0.date >= today && $0.date < todayEnd
        }

        for record in todayRecords where record.status != .done {
            guard let goalId = record.goalId else { continue }
            guard !seenGoalIds.contains(goalId) else { continue }
            seenGoalIds.add(goalId)

            if let goal = goalService.goals.first(where: { $0.id == goalId }), goal.status == .active {
                let duration = record.plannedMinutes > 0 ? record.plannedMinutes : goal.minSessionMinutes
                let urgency = deadlineUrgency(goal)
                items.append(PlannedItem(
                    goalId: goalId,
                    title: goal.title,
                    duration: duration,
                    score: urgency * Double(goal.weight) + 10,  // +10 carryover bonus
                    type: .carryover,
                    preferredTimeTags: goal.preferredTimeTags
                ))
            }
        }

        // B. Weekly habit gaps (only for goals with recurrence)
        let activeGoals = goalService.activeGoals()
        for goal in activeGoals {
            guard let rec = goal.recurrence else { continue }
            guard rec.allowedDays.contains(isoWeekday) else { continue }
            guard !seenGoalIds.contains(goal.id) else { continue }

            let thisWeekSessions = countThisWeekSessions(goalId: goal.id)
            if thisWeekSessions < rec.weeklyTargetSessions {
                let debt = rec.weeklyTargetSessions - thisWeekSessions
                let urgency = deadlineUrgency(goal)
                seenGoalIds.add(goal.id)
                items.append(PlannedItem(
                    goalId: goal.id,
                    title: goal.title,
                    duration: rec.perSessionMinutes,
                    score: urgency * Double(goal.weight) + Double(debt) * 2,
                    type: .habitGap,
                    preferredTimeTags: goal.preferredTimeTags
                ))
            }
        }

        // C. Deadline-urgent goals (≤7 days, including overdue)
        for goal in activeGoals {
            guard !seenGoalIds.contains(goal.id) else { continue }
            let daysLeft = goalService.daysUntilDeadline(goal)
            if daysLeft <= 7 {
                let duration = goal.recurrence?.perSessionMinutes ?? goal.minSessionMinutes
                let score: Double
                if daysLeft <= 0 {
                    score = Double(goal.weight) * 30  // Overdue: highest priority
                } else {
                    score = Double(8 - daysLeft) * Double(goal.weight) * 3
                }
                seenGoalIds.add(goal.id)
                items.append(PlannedItem(
                    goalId: goal.id,
                    title: goal.title,
                    duration: duration,
                    score: score,
                    type: .deadline,
                    preferredTimeTags: goal.preferredTimeTags
                ))
            }
        }

        return items
    }

    // MARK: - Scoring Helpers

    private func deadlineUrgency(_ goal: Goal) -> Double {
        let daysLeft = goalService.daysUntilDeadline(goal)
        if daysLeft <= 0 { return 8.0 }  // Overdue
        if daysLeft <= 3 { return 5.0 }
        if daysLeft <= 7 { return 3.0 }
        if daysLeft <= 14 { return 2.0 }
        return 1.0
    }

    private func countThisWeekSessions(goalId: String) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now())
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        return goalService.completions.values
            .filter { $0.goalId == goalId && $0.date >= weekStart && $0.status == .done }
            .count
    }

    private func allowedCreateSources(for item: PlannedItem) -> [ScheduleCreateSource] {
        var sources: [ScheduleCreateSource] = []

        if let goalId = item.goalId,
           let goal = goalService.goals.first(where: { $0.id == goalId && $0.status == .active }) {
            sources.append(ScheduleCreateSource(kind: .activeGoal, title: goal.title))
        }

        let matchingCompletions = goalService.completions.values.filter { record in
            if let goalId = item.goalId, record.goalId == goalId {
                return true
            }

            guard let eventTitle = record.eventTitle else { return false }
            return normalizedTitle(eventTitle) == normalizedTitle(item.title)
        }

        for record in matchingCompletions {
            if let eventTitle = record.eventTitle, !normalizedTitle(eventTitle).isEmpty {
                sources.append(ScheduleCreateSource(kind: .existingEvent, title: eventTitle))
            }
        }

        var deduped: [ScheduleCreateSource] = []
        var seen = Set<String>()
        for source in sources {
            let key = "\(source.kind)|\(normalizedTitle(source.title))"
            if seen.insert(key).inserted {
                deduped.append(source)
            }
        }
        return deduped
    }

    private func buildResultSummary(
        deniedCount: Int,
        confirmationCount: Int,
        hadCreateError: Bool
    ) -> String? {
        var parts: [String] = []

        if deniedCount > 0 || confirmationCount > 0 {
            switch (deniedCount > 0, confirmationCount > 0) {
            case (true, true):
                parts.append("정책상 거부된 \(deniedCount)개와 확인이 필요한 \(confirmationCount)개 항목은 캘린더에 쓰지 않고 제안으로 남겼습니다")
            case (true, false):
                parts.append("정책상 거부된 \(deniedCount)개 항목은 캘린더에 쓰지 않고 제안으로 남겼습니다")
            case (false, true):
                parts.append("확인이 필요한 \(confirmationCount)개 항목은 캘린더에 쓰지 않고 제안으로 남겼습니다")
            case (false, false):
                break
            }
        }

        if hadCreateError {
            parts.append("일부 일정 생성 실패 — 아침 브리핑에서 수동 확인")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    private func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    // MARK: - Free Slot Computation

    private func findFreeSlots(events: [CalendarEvent], on date: Date, profile: UserProfile) -> [TimeSlot] {
        let cal = Calendar.current

        // Safe hour clamping
        let startHour = max(0, min(23, profile.workStartHour))
        let endHour = max(startHour + 1, min(23, profile.workEndHour + 2))

        guard let dayStart = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: date),
              let dayEnd = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: date) else {
            return []
        }

        // Busy blocks from existing events (including all-day as blocking)
        var busy: [(Date, Date)] = events
            .filter { !$0.isAllDay }
            .compactMap { event in
                let s = max(event.startDate, dayStart)
                let e = min(event.endDate, dayEnd)
                return s < e ? (s, e) : nil  // Filter invalid intervals
            }
            .sorted { $0.0 < $1.0 }

        // Lunch block
        if let lunchStart = cal.date(bySettingHour: profile.lunchStartHour, minute: 0, second: 0, of: date),
           let lunchEnd = cal.date(bySettingHour: profile.lunchEndHour, minute: 0, second: 0, of: date) {
            busy.append((lunchStart, lunchEnd))
        }

        // Commute blocks (only within day window)
        let commuteSeconds = TimeInterval(profile.commuteMinutes * 60)
        if commuteSeconds > 0 {
            let commuteMorningStart = dayStart.addingTimeInterval(-commuteSeconds)
            if commuteMorningStart < dayStart {
                busy.append((commuteMorningStart, dayStart))
            }
            if let workEnd = cal.date(bySettingHour: profile.workEndHour, minute: 0, second: 0, of: date) {
                busy.append((workEnd, workEnd.addingTimeInterval(commuteSeconds)))
            }
        }

        busy.sort { $0.0 < $1.0 }

        // Find gaps ≥ 25 min
        var slots: [TimeSlot] = []
        var cursor = dayStart

        for (busyStart, busyEnd) in busy {
            if cursor < busyStart {
                let gap = busyStart.timeIntervalSince(cursor)
                if gap >= 25 * 60 {
                    slots.append(TimeSlot(start: cursor, end: busyStart, tag: timeTag(for: cursor, profile: profile)))
                }
            }
            cursor = max(cursor, busyEnd)
        }
        if cursor < dayEnd {
            let gap = dayEnd.timeIntervalSince(cursor)
            if gap >= 25 * 60 {
                slots.append(TimeSlot(start: cursor, end: dayEnd, tag: timeTag(for: cursor, profile: profile)))
            }
        }

        return slots
    }

    private func timeTag(for date: Date, profile: UserProfile) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < profile.lunchStartHour {
            return "AM-Deep"
        } else if hour < profile.workEndHour - 1 {
            return "PM-Deep"
        } else {
            return "PM-Light"
        }
    }

    // MARK: - Slot Assignment

    private func assignSlot(
        for item: PlannedItem,
        from slots: [TimeSlot],
        energyType: EnergyType,
        useFocusWindows: Bool
    ) -> TimeSlot? {
        let duration = TimeInterval(item.duration * 60)

        // Prefer slots matching preferred time tags aligned with energy type
        if useFocusWindows {
            let deepSlots = energyType.deepSlots
            let preferred = slots.filter { slot in
                slot.available >= duration && item.preferredTimeTags.contains(slot.tag) && deepSlots.contains(slot.tag)
            }
            if let slot = preferred.first {
                return TimeSlot(start: slot.start, end: slot.start.addingTimeInterval(duration), tag: slot.tag)
            }
        }

        // Second preference: just matching preferred time tags
        let tagMatch = slots.filter { slot in
            slot.available >= duration && item.preferredTimeTags.contains(slot.tag)
        }
        if let slot = tagMatch.first {
            return TimeSlot(start: slot.start, end: slot.start.addingTimeInterval(duration), tag: slot.tag)
        }

        // Fallback: first slot that fits
        for slot in slots where slot.available >= duration {
            return TimeSlot(start: slot.start, end: slot.start.addingTimeInterval(duration), tag: slot.tag)
        }

        return nil
    }

    /// Fixed: only split the overlapping slot, pass through non-overlapping ones unchanged
    private func consumeSlot(_ used: TimeSlot, from slots: [TimeSlot]) -> [TimeSlot] {
        var result: [TimeSlot] = []
        for slot in slots {
            // No overlap → keep as-is
            if slot.end <= used.start || slot.start >= used.end {
                result.append(slot)
                continue
            }

            // Overlapping slot → split into before/after portions
            if slot.start < used.start {
                let gap = used.start.timeIntervalSince(slot.start)
                if gap >= 25 * 60 {
                    result.append(TimeSlot(start: slot.start, end: used.start, tag: slot.tag))
                }
            }
            if used.end < slot.end {
                let gap = slot.end.timeIntervalSince(used.end)
                if gap >= 25 * 60 {
                    result.append(TimeSlot(start: used.end, end: slot.end, tag: slot.tag))
                }
            }
        }
        return result
    }

    // MARK: - Convert to ReviewSuggestions (for morning briefing)

    func suggestionsFromLastResult() -> [ReviewSuggestion] {
        guard let result = lastResult else { return [] }

        var suggestions: [ReviewSuggestion] = []

        // Auto-created events: read-only info cards (no action buttons needed)
        for item in result.created {
            suggestions.append(ReviewSuggestion(
                type: item.type,
                title: item.title,
                description: "자동 배치됨 · \(formatTime(item.assignedStart))~\(formatTime(item.assignedEnd))",
                goalId: item.goalId,
                proposedStart: item.assignedStart,
                proposedEnd: item.assignedEnd,
                proposedTitle: item.title,
                status: .accepted  // Already created — morning card shows as info only
            ))
        }

        // Suggestions: actionable cards
        for item in result.suggested {
            suggestions.append(ReviewSuggestion(
                type: item.type,
                title: item.title,
                description: "\(item.duration)분 · \(formatTime(item.assignedStart))에 배치할까요?",
                goalId: item.goalId,
                proposedStart: item.assignedStart,
                proposedEnd: item.assignedEnd,
                proposedTitle: item.title
            ))
        }

        return suggestions
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone(identifier: "Asia/Seoul")
        return fmt.string(from: date)
    }
}

// MARK: - Time Slot

struct TimeSlot {
    let start: Date
    let end: Date
    let tag: String  // "AM-Deep", "PM-Deep", "PM-Light"

    var available: TimeInterval { end.timeIntervalSince(start) }
}
