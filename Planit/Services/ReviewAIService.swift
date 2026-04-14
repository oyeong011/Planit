import Foundation

// MARK: - AI Plan Result

struct ReviewAIPlan {
    struct PlannedEvent {
        let title: String
        let start: Date
        let end: Date
    }
    var events: [PlannedEvent]
    var summary: String
    var error: String?
    var isEmpty: Bool { events.isEmpty }
}

// MARK: - ReviewAIService

@MainActor
final class ReviewAIService {

    private let goalService: GoalService
    private let calendarService: GoogleCalendarService?

    init(goalService: GoalService, calendarService: GoogleCalendarService?) {
        self.goalService = goalService
        self.calendarService = calendarService
    }

    // MARK: - Main Entry

    /// 오늘 리뷰 데이터를 바탕으로 내일 계획을 AI가 생성합니다.
    func generateTomorrowPlan(
        reviewed: [(title: String, status: CompletionStatus, start: Date, end: Date)]
    ) async -> ReviewAIPlan {
        guard let claudePath = AIService.findClaudePath() else {
            return ReviewAIPlan(events: [], summary: "", error: "Claude가 설치되지 않았습니다")
        }

        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!

        // 1. 내일 기존 이벤트 조회
        let tomorrowEvents = (try? await calendarService?.fetchEvents(for: tomorrow)) ?? []
        let freeSlots = computeFreeSlots(events: tomorrowEvents, on: tomorrow)

        // 2. 프롬프트 생성
        let prompt = buildPrompt(reviewed: reviewed, tomorrowEvents: tomorrowEvents,
                                  freeSlots: freeSlots, tomorrow: tomorrow)

        // 3. Claude CLI 호출 (블로킹 — 메인 액터 외부에서 실행)
        let response = await Task.detached(priority: .userInitiated) {
            AIService.runClaudeOneShot(prompt: prompt, claudePath: claudePath)
        }.value

        // 4. JSON 파싱
        return parseResponse(response, tomorrow: tomorrow, freeSlots: freeSlots)
    }

    // MARK: - Prompt Builder

    private func buildPrompt(
        reviewed: [(title: String, status: CompletionStatus, start: Date, end: Date)],
        tomorrowEvents: [CalendarEvent],
        freeSlots: [(Date, Date)],
        tomorrow: Date
    ) -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd (EEEE)"
        dateFmt.locale = Locale(identifier: "en_US")

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.timeZone = TimeZone.current

        let profile = goalService.profile
        let goals = goalService.activeGoals()

        var p = """
        You are a realistic schedule optimizer. Humans are not perfect — plans always go off-track. \
        Adjust tomorrow's schedule based on today's review.

        TODAY: \(dateFmt.string(from: Date()))
        """

        let done = reviewed.filter { $0.status == .done }
        let missed = reviewed.filter { $0.status != .done && $0.status != .skipped }

        if !done.isEmpty {
            p += "\n\nCOMPLETED TODAY:\n"
            done.forEach { p += "- \($0.title) (\(timeFmt.string(from: $0.start))-\(timeFmt.string(from: $0.end)))\n" }
        }
        if !missed.isEmpty {
            p += "\nMISSED (reschedule these first):\n"
            missed.forEach { p += "- \($0.title) (\(timeFmt.string(from: $0.start))-\(timeFmt.string(from: $0.end)))\n" }
        }

        if !goals.isEmpty {
            p += "\n\nACTIVE GOALS:\n"
            goals.forEach { g in
                let days = goalService.daysUntilDeadline(g)
                let min = g.recurrence?.perSessionMinutes ?? g.minSessionMinutes
                p += "- \(g.title): \(min)min/session, D-\(days)\n"
            }
        }

        p += "\n\nTOMORROW: \(dateFmt.string(from: tomorrow))\n"

        let fixed = tomorrowEvents.filter { !$0.isAllDay }
        if !fixed.isEmpty {
            p += "FIXED EVENTS:\n"
            fixed.forEach { p += "- \($0.title) (\(timeFmt.string(from: $0.startDate))-\(timeFmt.string(from: $0.endDate)))\n" }
        }

        p += "\nFREE SLOTS:\n"
        freeSlots.forEach { p += "- \(timeFmt.string(from: $0.0))-\(timeFmt.string(from: $0.1))\n" }

        let cap = profile.weekdayCapacityMinutes
        p += "\nDAILY GOAL CAPACITY: \(cap) minutes\n"

        // ISO 날짜 포맷 예시
        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"
        isoFmt.timeZone = TimeZone.current
        let tomorrowDateStr = isoFmt.string(from: tomorrow)

        p += """

        RULES:
        1. Reschedule missed items with priority
        2. Add goal sessions only if capacity allows
        3. Keep each event 25-90 minutes
        4. Leave 15min buffers between events
        5. Don't overload — be realistic

        Respond ONLY with valid JSON (no markdown, no extra text):
        {"events":[{"title":"...","start":"\(tomorrowDateStr)THH:MM:SS","end":"\(tomorrowDateStr)THH:MM:SS"}],"summary":"one sentence"}
        """

        return p
    }

    // MARK: - Response Parser

    private func parseResponse(_ response: String, tomorrow: Date, freeSlots: [(Date, Date)]) -> ReviewAIPlan {
        // JSON 추출 (마크다운 코드블록 처리)
        var jsonStr = response
        if let start = response.range(of: "{"),
           let end = response.range(of: "}", options: .backwards) {
            jsonStr = String(response[start.lowerBound...end.upperBound])
        }

        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallbackPlan(tomorrow: tomorrow, freeSlots: freeSlots, error: "AI 응답 파싱 실패")
        }

        let summary = json["summary"] as? String ?? ""
        let eventsArray = json["events"] as? [[String: String]] ?? []

        let localFmt = DateFormatter()
        localFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        localFmt.timeZone = TimeZone.current

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]

        var events: [ReviewAIPlan.PlannedEvent] = []
        for e in eventsArray {
            guard let title = e["title"], !title.isEmpty,
                  let startStr = e["start"], let endStr = e["end"] else { continue }

            let start = localFmt.date(from: startStr) ?? isoFmt.date(from: startStr)
            let end = localFmt.date(from: endStr) ?? isoFmt.date(from: endStr)

            guard let s = start, let en = end, en > s else { continue }
            guard Calendar.current.isDate(s, inSameDayAs: tomorrow) else { continue }

            events.append(ReviewAIPlan.PlannedEvent(title: title, start: s, end: en))
        }

        if events.isEmpty {
            return fallbackPlan(tomorrow: tomorrow, freeSlots: freeSlots, error: "AI가 일정을 생성하지 않음")
        }

        return ReviewAIPlan(events: events, summary: summary)
    }

    // MARK: - Fallback (AI 실패 시 규칙 기반)

    private func fallbackPlan(tomorrow: Date, freeSlots: [(Date, Date)], error: String) -> ReviewAIPlan {
        let goals = goalService.activeGoals()
        var events: [ReviewAIPlan.PlannedEvent] = []
        var slots = freeSlots

        for goal in goals.prefix(3) {
            let duration = TimeInterval((goal.recurrence?.perSessionMinutes ?? goal.minSessionMinutes) * 60)
            guard let slot = slots.first(where: { $0.1.timeIntervalSince($0.0) >= duration }) else { continue }
            events.append(ReviewAIPlan.PlannedEvent(title: goal.title,
                                                     start: slot.0,
                                                     end: slot.0.addingTimeInterval(duration)))
            slots.removeFirst()
        }

        return ReviewAIPlan(events: events, summary: "기본 계획 (AI 응답 없음)", error: error)
    }

    // MARK: - Free Slot Computation

    private func computeFreeSlots(events: [CalendarEvent], on date: Date) -> [(Date, Date)] {
        let cal = Calendar.current
        let profile = goalService.profile
        guard let dayStart = cal.date(bySettingHour: profile.workStartHour, minute: 0, second: 0, of: date),
              let dayEnd   = cal.date(bySettingHour: profile.workEndHour,   minute: 0, second: 0, of: date) else { return [] }

        var busy: [(Date, Date)] = events
            .filter { !$0.isAllDay }
            .compactMap { e -> (Date, Date)? in
                let s = max(e.startDate, dayStart)
                let en = min(e.endDate, dayEnd)
                return s < en ? (s, en) : nil
            }

        if let l0 = cal.date(bySettingHour: profile.lunchStartHour, minute: 0, second: 0, of: date),
           let l1 = cal.date(bySettingHour: profile.lunchEndHour,   minute: 0, second: 0, of: date) {
            busy.append((l0, l1))
        }

        busy.sort { $0.0 < $1.0 }

        var slots: [(Date, Date)] = []
        var cursor = dayStart
        for (bs, be) in busy {
            if cursor < bs && bs.timeIntervalSince(cursor) >= 25 * 60 {
                slots.append((cursor, bs))
            }
            cursor = max(cursor, be)
        }
        if cursor < dayEnd && dayEnd.timeIntervalSince(cursor) >= 25 * 60 {
            slots.append((cursor, dayEnd))
        }
        return slots
    }
}
