import Foundation
import Testing
@testable import Calen

private func fixedDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}

@Test func todoGrassStats_buildsThirtyDaysEndingToday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = fixedDate("2026-04-20T12:00:00Z")

    let stats = TodoGrassStats.make(todos: [], reminders: [], now: now, calendar: calendar)

    #expect(stats.days.count == 30)
    #expect(calendar.isDate(stats.days.first!.date, inSameDayAs: fixedDate("2026-03-22T00:00:00Z")))
    #expect(calendar.isDate(stats.days.last!.date, inSameDayAs: fixedDate("2026-04-20T00:00:00Z")))
}

@Test func todoGrassStats_countsDoneAndTotalPerScheduledDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = fixedDate("2026-04-20T12:00:00Z")
    let category = UUID()
    let targetDay = fixedDate("2026-04-18T09:00:00Z")
    let outsideWindow = fixedDate("2026-03-01T09:00:00Z")
    let todos = [
        TodoItem(title: "done local", categoryID: category, isCompleted: true, date: targetDay),
        TodoItem(title: "open local", categoryID: category, isCompleted: false, date: targetDay),
        TodoItem(title: "old local", categoryID: category, isCompleted: true, date: outsideWindow),
    ]
    let reminders = [
        TodoItem(title: "done reminder", categoryID: category, isCompleted: true, date: targetDay, source: .appleReminder)
    ]

    let stats = TodoGrassStats.make(todos: todos, reminders: reminders, now: now, calendar: calendar)
    let day = stats.days.first { calendar.isDate($0.date, inSameDayAs: targetDay) }

    #expect(day?.done == 2)
    #expect(day?.total == 3)
    #expect(stats.totalDone == 2)
    #expect(stats.totalTodos == 3)
    #expect(stats.maxDoneInDay == 2)
}

@Test func todoGrassStats_currentStreakRequiresEveryTodoDone() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = fixedDate("2026-04-20T12:00:00Z")
    let category = UUID()
    let today = fixedDate("2026-04-20T09:00:00Z")
    let yesterday = fixedDate("2026-04-19T09:00:00Z")
    let twoDaysAgo = fixedDate("2026-04-18T09:00:00Z")
    let threeDaysAgo = fixedDate("2026-04-17T09:00:00Z")
    let todos = [
        TodoItem(title: "today done", categoryID: category, isCompleted: true, date: today),
        TodoItem(title: "yesterday done", categoryID: category, isCompleted: true, date: yesterday),
        TodoItem(title: "two days done", categoryID: category, isCompleted: true, date: twoDaysAgo),
        TodoItem(title: "two days open", categoryID: category, isCompleted: false, date: twoDaysAgo),
        TodoItem(title: "three days done", categoryID: category, isCompleted: true, date: threeDaysAgo),
    ]

    let stats = TodoGrassStats.make(todos: todos, reminders: [], now: now, calendar: calendar)

    #expect(stats.currentFullCompletionStreak == 2)
}
