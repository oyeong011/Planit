import Foundation
import Testing
@testable import Calen

private func fixedDate(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso)!
}

@Test func userContextTimePatternAnalysis_identifiesPeakAndFragmentation() {
    let events = [
        CalendarEvent(id: "1", title: "Deep work", startDate: fixedDate("2026-04-13T09:00:00+09:00"), endDate: fixedDate("2026-04-13T11:00:00+09:00"), color: .blue, isAllDay: false),
        CalendarEvent(id: "2", title: "Review", startDate: fixedDate("2026-04-13T13:00:00+09:00"), endDate: fixedDate("2026-04-13T14:00:00+09:00"), color: .blue, isAllDay: false),
        CalendarEvent(id: "3", title: "Client sync", startDate: fixedDate("2026-04-14T09:30:00+09:00"), endDate: fixedDate("2026-04-14T10:00:00+09:00"), color: .blue, isAllDay: false),
        CalendarEvent(id: "4", title: "Planning", startDate: fixedDate("2026-04-14T10:30:00+09:00"), endDate: fixedDate("2026-04-14T11:00:00+09:00"), color: .blue, isAllDay: false),
    ]

    let analysis = UserContextService.buildTimePatternAnalysis(events: events, now: fixedDate("2026-04-17T12:00:00+09:00"))

    #expect(analysis.contains("peak busy window: morning"))
    #expect(analysis.contains("fragmentation risk"))
    #expect(analysis.contains("AI prompt use:"))
}

@Test func userContextTaskTendencyAnalysis_summarizesCompletionAndCategories() {
    let study = TodoCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "공부", colorHex: "#6699FF")
    let life = TodoCategory(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "일상", colorHex: "#999999")
    let todos = [
        TodoItem(title: "정보처리기사 실기 복습", categoryID: study.id, isCompleted: true, date: fixedDate("2026-04-16T00:00:00+09:00")),
        TodoItem(title: "기출 문제 풀기", categoryID: study.id, isCompleted: false, date: fixedDate("2026-04-17T00:00:00+09:00")),
        TodoItem(title: "청소", categoryID: life.id, isCompleted: false, date: fixedDate("2026-04-15T00:00:00+09:00")),
    ]

    let analysis = UserContextService.buildTaskTendencyAnalysis(todos: todos, categories: [study, life], now: fixedDate("2026-04-17T12:00:00+09:00"))

    #expect(analysis.contains("completion rate: 33%"))
    #expect(analysis.contains("top category: 공부"))
    #expect(analysis.contains("overdue open tasks: 1"))
}

@Test func userContextGoalStatusAnalysis_flagsAtRiskGoalsAndChangeRate() {
    let goal = Goal(
        id: "goal-1",
        level: .month,
        title: "정보처리기사 합격",
        startDate: fixedDate("2026-04-01T00:00:00+09:00"),
        dueDate: fixedDate("2026-04-20T00:00:00+09:00"),
        targetHours: 20,
        recurrence: RecurrencePlan(weeklyTargetSessions: 4, perSessionMinutes: 60, allowedDays: [1, 2, 3, 4])
    )
    let completions = [
        "a": CompletionRecord(eventId: "a", goalId: "goal-1", date: fixedDate("2026-04-15T09:00:00+09:00"), status: .done, plannedMinutes: 60, actualMinutes: 45),
        "b": CompletionRecord(eventId: "b", goalId: "goal-1", date: fixedDate("2026-04-16T09:00:00+09:00"), status: .moved, plannedMinutes: 60),
        "c": CompletionRecord(eventId: "c", goalId: "goal-1", date: fixedDate("2026-04-17T09:00:00+09:00"), status: .skipped, plannedMinutes: 60),
    ]

    let analysis = UserContextService.buildGoalStatusAnalysis(goals: [goal], completions: completions, now: fixedDate("2026-04-17T12:00:00+09:00"))

    #expect(analysis.contains("active goals: 1"))
    #expect(analysis.contains("at-risk goals: 정보처리기사 합격"))
    #expect(analysis.contains("moved/skipped rate: 67%"))
}
