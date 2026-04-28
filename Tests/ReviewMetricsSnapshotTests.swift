import Foundation
import Testing
@testable import Calen

private func reviewFixedDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}

private func reviewTodo(
    id: UUID = UUID(),
    title: String,
    date: Date,
    isCompleted: Bool = false,
    googleEventId: String? = nil,
    source: TodoSource = .local
) -> TodoItem {
    TodoItem(
        id: id,
        title: title,
        categoryID: UUID(),
        isCompleted: isCompleted,
        date: date,
        googleEventId: googleEventId,
        source: source
    )
}

private func reviewEvent(
    id: String,
    start: Date,
    end: Date,
    title: String = "Event"
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        title: title,
        startDate: start,
        endDate: end,
        color: .blue,
        isAllDay: false,
        calendarName: "Work",
        calendarID: "google:work",
        source: .google
    )
}

@Suite("ReviewMetricsSnapshot")
struct ReviewMetricsSnapshotTests {
    @Test("input signature changes when completion changes without count changes")
    func inputSignatureTracksCompletionChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = reviewFixedDate("2026-04-20T12:00:00Z")
        let todoID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let openTodo = reviewTodo(id: todoID, title: "same todo", date: now, isCompleted: false)
        let doneTodo = reviewTodo(id: todoID, title: "same todo", date: now, isCompleted: true)

        let openSignature = ReviewMetricsSnapshot.InputSignature.make(
            todos: [openTodo],
            reminders: [],
            calendarEvents: [],
            historyEvents: [],
            completedEventIDs: [],
            habitCount: 0,
            goalCount: 0,
            now: now,
            calendar: calendar
        )
        let doneSignature = ReviewMetricsSnapshot.InputSignature.make(
            todos: [doneTodo],
            reminders: [],
            calendarEvents: [],
            historyEvents: [],
            completedEventIDs: [],
            habitCount: 0,
            goalCount: 0,
            now: now,
            calendar: calendar
        )

        #expect(openSignature != doneSignature)
    }

    @Test("input signature treats completed event IDs as order independent")
    func inputSignatureSortsCompletedEventIDs() {
        let now = reviewFixedDate("2026-04-20T12:00:00Z")
        let first = ReviewMetricsSnapshot.InputSignature.make(
            todos: [],
            reminders: [],
            calendarEvents: [],
            historyEvents: [],
            completedEventIDs: ["b", "a"],
            habitCount: 1,
            goalCount: 2,
            now: now
        )
        let second = ReviewMetricsSnapshot.InputSignature.make(
            todos: [],
            reminders: [],
            calendarEvents: [],
            historyEvents: [],
            completedEventIDs: ["a", "b"],
            habitCount: 1,
            goalCount: 2,
            now: now
        )

        #expect(first == second)
    }

    @Test("input signature changes when habit completion changes without count changes")
    func inputSignatureTracksHabitCompletionChanges() {
        let now = reviewFixedDate("2026-04-20T12:00:00Z")
        let openHabit = Habit(name: "Read", emoji: "📚", colorName: "blue", weeklyTarget: 3)
        var doneHabit = openHabit
        doneHabit.completedDates = ["2026-04-20"]

        let openSignature = ReviewMetricsSnapshot.InputSignature.make(
            todos: [],
            reminders: [],
            calendarEvents: [],
            historyEvents: [],
            completedEventIDs: [],
            habits: [openHabit],
            habitCount: 1,
            goalCount: 0,
            now: now
        )
        let doneSignature = ReviewMetricsSnapshot.InputSignature.make(
            todos: [],
            reminders: [],
            calendarEvents: [],
            historyEvents: [],
            completedEventIDs: [],
            habits: [doneHabit],
            habitCount: 1,
            goalCount: 0,
            now: now
        )

        #expect(openSignature != doneSignature)
    }

    @Test("input signature treats habit completion date ordering as order independent")
    func inputSignatureSortsHabitCompletionDates() {
        let now = reviewFixedDate("2026-04-20T12:00:00Z")
        var firstHabit = Habit(name: "Read", emoji: "📚", colorName: "blue", weeklyTarget: 3)
        var secondHabit = firstHabit
        firstHabit.completedDates = ["2026-04-19", "2026-04-20"]
        secondHabit.completedDates = ["2026-04-20", "2026-04-19"]

        let first = ReviewMetricsSnapshot.InputSignature.make(
            todos: [],
            reminders: [],
            calendarEvents: [],
            historyEvents: [],
            completedEventIDs: [],
            habits: [firstHabit],
            habitCount: 1,
            goalCount: 0,
            now: now
        )
        let second = ReviewMetricsSnapshot.InputSignature.make(
            todos: [],
            reminders: [],
            calendarEvents: [],
            historyEvents: [],
            completedEventIDs: [],
            habits: [secondHabit],
            habitCount: 1,
            goalCount: 0,
            now: now
        )

        #expect(first == second)
    }

    @Test("input signature treats review source ordering as order independent")
    func inputSignatureSortsReviewSources() {
        let now = reviewFixedDate("2026-04-20T12:00:00Z")
        let firstTodo = reviewTodo(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "first",
            date: reviewFixedDate("2026-04-20T08:00:00Z"),
            isCompleted: true,
            googleEventId: "todo-a"
        )
        let secondTodo = reviewTodo(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "second",
            date: reviewFixedDate("2026-04-19T08:00:00Z"),
            isCompleted: false,
            googleEventId: "todo-b"
        )
        let firstReminder = reviewTodo(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "first reminder",
            date: reviewFixedDate("2026-04-18T08:00:00Z"),
            source: .appleReminder
        )
        let secondReminder = reviewTodo(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            title: "second reminder",
            date: reviewFixedDate("2026-04-17T08:00:00Z"),
            source: .appleReminder
        )
        let firstEvent = reviewEvent(
            id: "event-a",
            start: reviewFixedDate("2026-04-20T09:00:00Z"),
            end: reviewFixedDate("2026-04-20T10:00:00Z")
        )
        let secondEvent = reviewEvent(
            id: "event-b",
            start: reviewFixedDate("2026-04-19T09:00:00Z"),
            end: reviewFixedDate("2026-04-19T10:00:00Z")
        )
        let firstHistoryEvent = reviewEvent(
            id: "history-a",
            start: reviewFixedDate("2026-04-18T09:00:00Z"),
            end: reviewFixedDate("2026-04-18T10:00:00Z")
        )
        let secondHistoryEvent = reviewEvent(
            id: "history-b",
            start: reviewFixedDate("2026-04-17T09:00:00Z"),
            end: reviewFixedDate("2026-04-17T10:00:00Z")
        )

        let first = ReviewMetricsSnapshot.InputSignature.make(
            todos: [firstTodo, secondTodo],
            reminders: [firstReminder, secondReminder],
            calendarEvents: [firstEvent, secondEvent],
            historyEvents: [firstHistoryEvent, secondHistoryEvent],
            completedEventIDs: ["event-a"],
            habitCount: 1,
            goalCount: 2,
            now: now
        )
        let second = ReviewMetricsSnapshot.InputSignature.make(
            todos: [secondTodo, firstTodo],
            reminders: [secondReminder, firstReminder],
            calendarEvents: [secondEvent, firstEvent],
            historyEvents: [secondHistoryEvent, firstHistoryEvent],
            completedEventIDs: ["event-a"],
            habitCount: 1,
            goalCount: 2,
            now: now
        )

        #expect(first == second)
    }

    @Test("precomputes expensive builders once")
    func precomputesExpensiveBuildersOnce() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = reviewFixedDate("2026-04-20T12:00:00Z")
        let weekDates = ReviewMetricsSnapshot.weekDates(endingAt: now, calendar: calendar)
        var weeklyBuilderCallCount = 0
        var grassBuilderCallCount = 0
        let sentinelWeekly = [ReviewMetricsSnapshot.DayCompletion(date: calendar.startOfDay(for: now), done: 2, total: 3)]
        let sentinelGrass = TodoGrassStats.make(todos: [], reminders: [], now: now, calendar: calendar)

        let snapshot = ReviewMetricsSnapshot.make(
            weekDates: weekDates,
            eventsByDay: [:],
            todos: [],
            reminders: [],
            historyEvents: [],
            completedEventIDs: [],
            habits: [],
            goals: [],
            now: now,
            calendar: calendar,
            weeklyCompletionBuilder: { dates, eventsByDay, todos, reminders, completedEventIDs, calendar in
                weeklyBuilderCallCount += 1
                #expect(dates == weekDates)
                #expect(eventsByDay.isEmpty)
                #expect(todos.isEmpty)
                #expect(reminders.isEmpty)
                #expect(completedEventIDs.isEmpty)
                return sentinelWeekly
            },
            todoGrassStatsBuilder: { todos, reminders, historyEvents, completedEventIDs, snapshotNow, calendar in
                grassBuilderCallCount += 1
                #expect(todos.isEmpty)
                #expect(reminders.isEmpty)
                #expect(historyEvents.isEmpty)
                #expect(completedEventIDs.isEmpty)
                #expect(snapshotNow == now)
                return sentinelGrass
            }
        )

        #expect(snapshot.weeklyCompletion == sentinelWeekly)
        #expect(snapshot.weeklyCompletion == sentinelWeekly)
        #expect(snapshot.todoGrassStats == sentinelGrass)
        #expect(snapshot.todoGrassStats == sentinelGrass)
        #expect(weeklyBuilderCallCount == 1)
        #expect(grassBuilderCallCount == 1)
    }

    @Test("events by day scans calendar events once and expands only visible week days")
    func eventsByDayGroupsCalendarEventsInOnePass() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = reviewFixedDate("2026-04-20T12:00:00Z")
        let weekDates = ReviewMetricsSnapshot.weekDates(endingAt: now, calendar: calendar)
        let mirrorTodo = reviewTodo(
            title: "todo mirror",
            date: reviewFixedDate("2026-04-18T08:00:00Z"),
            googleEventId: "todo-mirror"
        )
        let overnight = reviewEvent(
            id: "overnight",
            start: reviewFixedDate("2026-04-19T23:00:00Z"),
            end: reviewFixedDate("2026-04-20T01:00:00Z")
        )
        let allDay = CalendarEvent(
            id: "all-day",
            title: "all day",
            startDate: reviewFixedDate("2026-04-18T00:00:00Z"),
            endDate: reviewFixedDate("2026-04-20T00:00:00Z"),
            color: .blue,
            isAllDay: true,
            calendarName: "Work",
            calendarID: "google:work",
            source: .google
        )
        let mirrorEvent = reviewEvent(
            id: "todo-mirror",
            start: reviewFixedDate("2026-04-18T09:00:00Z"),
            end: reviewFixedDate("2026-04-18T10:00:00Z")
        )

        let grouped = ReviewMetricsSnapshot.eventsByDay(
            weekDates: weekDates,
            calendarEvents: [overnight, allDay, mirrorEvent],
            todos: [mirrorTodo],
            calendar: calendar
        )

        let apr18 = calendar.startOfDay(for: reviewFixedDate("2026-04-18T00:00:00Z"))
        let apr19 = calendar.startOfDay(for: reviewFixedDate("2026-04-19T00:00:00Z"))
        let apr20 = calendar.startOfDay(for: reviewFixedDate("2026-04-20T00:00:00Z"))

        #expect(grouped[apr18]?.map(\.id) == ["all-day"])
        #expect(grouped[apr19]?.map(\.id).sorted() == ["all-day", "overnight"])
        #expect(grouped[apr20]?.map(\.id) == ["overnight"])
        #expect(!grouped.values.flatMap { $0 }.contains { $0.id == "todo-mirror" })
    }

    @Test("empty snapshot provides stable zero metrics")
    func emptySnapshotProvidesStableZeroMetrics() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = reviewFixedDate("2026-04-20T12:00:00Z")

        let snapshot = ReviewMetricsSnapshot.empty(now: now, calendar: calendar)

        #expect(snapshot.weeklyCompletion.count == 7)
        #expect(snapshot.weeklyCompletion.allSatisfy { $0.done == 0 && $0.total == 0 })
        #expect(snapshot.todoGrassStats.totalDone == 0)
        #expect(snapshot.todoGrassStats.totalTodos == 0)
        #expect(snapshot.habitCount == 0)
        #expect(snapshot.goalCount == 0)
    }

    @Test("builds weekly completion and grass stats from review sources")
    func buildsWeeklyCompletionAndGrassStats() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1

        let now = reviewFixedDate("2026-04-20T12:00:00Z")
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let weekDates = ReviewMetricsSnapshot.weekDates(endingAt: now, calendar: calendar)

        let eventsByDay: [Date: [CalendarEvent]] = [
            today: [
                reviewEvent(
                    id: "today-done",
                    start: reviewFixedDate("2026-04-20T09:00:00Z"),
                    end: reviewFixedDate("2026-04-20T10:00:00Z")
                )
            ],
            yesterday: [
                reviewEvent(
                    id: "yesterday-open",
                    start: reviewFixedDate("2026-04-19T09:00:00Z"),
                    end: reviewFixedDate("2026-04-19T10:00:00Z")
                )
            ]
        ]
        let todos = [
            reviewTodo(title: "today done", date: reviewFixedDate("2026-04-20T08:00:00Z"), isCompleted: true),
            reviewTodo(title: "yesterday open", date: reviewFixedDate("2026-04-19T08:00:00Z"), isCompleted: false),
            reviewTodo(
                title: "mirrored todo",
                date: reviewFixedDate("2026-04-18T08:00:00Z"),
                isCompleted: true,
                googleEventId: "todo-mirror"
            )
        ]
        let reminders = [
            reviewTodo(
                title: "today reminder",
                date: reviewFixedDate("2026-04-20T07:00:00Z"),
                isCompleted: true,
                source: .appleReminder
            )
        ]
        let historyEvents = [
            reviewEvent(
                id: "history-done",
                start: reviewFixedDate("2026-04-17T09:00:00Z"),
                end: reviewFixedDate("2026-04-17T10:00:00Z")
            ),
            reviewEvent(
                id: "todo-mirror",
                start: reviewFixedDate("2026-04-18T09:00:00Z"),
                end: reviewFixedDate("2026-04-18T10:00:00Z")
            )
        ]
        let habits = [
            Habit(name: "Read", emoji: "📚", colorName: "blue", weeklyTarget: 3),
            Habit(name: "Run", emoji: "🏃", colorName: "green", weeklyTarget: 2)
        ]
        let goals = [
            ChatGoal(title: "Ship Planit", targets: ["Launch"], keywords: ["Planit"], timeline: .thisMonth)
        ]

        let snapshot = ReviewMetricsSnapshot.make(
            weekDates: weekDates,
            eventsByDay: eventsByDay,
            todos: todos,
            reminders: reminders,
            historyEvents: historyEvents,
            completedEventIDs: ["today-done", "history-done"],
            habits: habits,
            goals: goals,
            now: now,
            calendar: calendar
        )

        let todayStats = snapshot.weeklyCompletion.last
        #expect(todayStats?.done == 3)
        #expect(todayStats?.total == 3)

        let yesterdayStats = snapshot.weeklyCompletion.first { calendar.isDate($0.date, inSameDayAs: yesterday) }
        #expect(yesterdayStats?.done == 0)
        #expect(yesterdayStats?.total == 2)

        let historyDay = snapshot.todoGrassStats.days.first {
            calendar.isDate($0.date, inSameDayAs: reviewFixedDate("2026-04-17T00:00:00Z"))
        }
        #expect(historyDay?.done == 1)
        #expect(historyDay?.total == 1)
        #expect(snapshot.todoGrassStats.totalDone == 4)
        #expect(snapshot.todoGrassStats.totalTodos == 5)
        #expect(snapshot.habitCount == 2)
        #expect(snapshot.goalCount == 1)
    }
}
