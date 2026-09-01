import Foundation
import Testing
@testable import Calen

@MainActor
struct EveningRescheduleTests {
    @Test
    func preservesYesterdayIncompleteRecordReason() throws {
        let calendar = makeCalendar()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 21, calendar: calendar))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let categoryID = UUID()

        let todo = TodoItem(title: "밀린 기획 정리", categoryID: categoryID, date: yesterday)
        let goalService = GoalService()
        goalService.completions = [
            "todo:\(todo.id.uuidString)": CompletionRecord(
                eventId: "todo:\(todo.id.uuidString)",
                eventTitle: todo.title,
                goalId: nil,
                date: yesterday,
                status: .skipped,
                plannedMinutes: 30
            )
        ]

        let service = ReviewService(goalService: goalService, calendarService: nil)
        service.refreshEveningReschedulePlan(
            todos: [todo],
            events: [],
            now: now
        )

        let item = try #require(service.eveningReschedulePlan.items.first)
        #expect(item.todoId == todo.id)
        #expect(item.reason.contains("건너뛴 기록"))
    }

    @Test
    func includesOnlyEligibleOverdueTodosWithRecoveryReasons() throws {
        let calendar = makeCalendar()
        let now = try #require(makeDate(year: 2026, month: 5, day: 4, hour: 21, calendar: calendar))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        let categoryID = UUID()

        let overdueTodo = TodoItem(title: "밀린 보고서", categoryID: categoryID, date: yesterday)
        let malformedOverdueTodo = TodoItem(title: "   ", categoryID: categoryID, date: yesterday)
        let completedTodo = TodoItem(title: "완료된 일", categoryID: categoryID, isCompleted: true, date: yesterday)
        let futureTodo = TodoItem(title: "미래 할 일", categoryID: categoryID, date: tomorrow)

        let service = ReviewService(goalService: GoalService(), calendarService: nil)
        service.refreshEveningReschedulePlan(
            todos: [overdueTodo, malformedOverdueTodo, completedTodo, futureTodo],
            events: [],
            now: now
        )

        let itemsByID = Dictionary(uniqueKeysWithValues: service.eveningReschedulePlan.items.map { ($0.todoId, $0) })

        #expect(itemsByID[overdueTodo.id] != nil)
        #expect(itemsByID[malformedOverdueTodo.id] != nil)
        #expect(itemsByID[completedTodo.id] == nil)
        #expect(itemsByID[futureTodo.id] == nil)
        #expect(itemsByID[overdueTodo.id]?.reason.contains("완료 기록이 없어") == true)
        #expect(itemsByID[malformedOverdueTodo.id]?.reason.contains("완료 기록이 없어") == true)
        #expect(itemsByID[malformedOverdueTodo.id]?.title == "미완료 할 일")
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }
}
