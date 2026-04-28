import Foundation

struct ReviewMetricsSnapshot: Equatable {
    struct InputSignature: Equatable {
        struct TodoKey: Hashable {
            let id: UUID
            let day: Date
            let isCompleted: Bool
            let googleEventId: String?
            let source: String
            let appleReminderIdentifier: String?
        }

        struct EventKey: Hashable {
            let id: String
            let startDate: Date
            let endDate: Date
            let isAllDay: Bool
        }

        struct HabitKey: Hashable {
            let id: UUID
            let weeklyTarget: Int
            let completedDates: Set<String>
            let startDateKey: String?
            let endDateKey: String?
        }

        let today: Date
        let todos: Set<TodoKey>
        let reminders: Set<TodoKey>
        let calendarEvents: Set<EventKey>
        let historyEvents: Set<EventKey>
        let completedEventIDs: Set<String>
        let habits: Set<HabitKey>
        let habitCount: Int
        let goalCount: Int

        static func make(
            todos: [TodoItem],
            reminders: [TodoItem],
            calendarEvents: [CalendarEvent],
            historyEvents: [CalendarEvent],
            completedEventIDs: Set<String>,
            habits: [Habit] = [],
            habitCount: Int,
            goalCount: Int,
            now: Date = Date(),
            calendar: Calendar = .current
        ) -> InputSignature {
            InputSignature(
                today: calendar.startOfDay(for: now),
                todos: Set(todos.map { TodoKey(todo: $0, calendar: calendar) }),
                reminders: Set(reminders.map { TodoKey(todo: $0, calendar: calendar) }),
                calendarEvents: Set(calendarEvents.map(EventKey.init(event:))),
                historyEvents: Set(historyEvents.map(EventKey.init(event:))),
                completedEventIDs: completedEventIDs,
                habits: Set(habits.map(HabitKey.init(habit:))),
                habitCount: habitCount,
                goalCount: goalCount
            )
        }
    }

    struct DayCompletion: Equatable {
        let date: Date
        let done: Int
        let total: Int

        var rate: Double {
            total > 0 ? Double(done) / Double(total) : 0
        }
    }

    let weeklyCompletion: [DayCompletion]
    let todoGrassStats: TodoGrassStats
    let habitCount: Int
    let goalCount: Int

    static func empty(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReviewMetricsSnapshot {
        let weekDates = weekDates(endingAt: now, calendar: calendar)
        return ReviewMetricsSnapshot(
            weeklyCompletion: weekDates.map { date in
                DayCompletion(date: calendar.startOfDay(for: date), done: 0, total: 0)
            },
            todoGrassStats: TodoGrassStats.make(todos: [], reminders: [], now: now, calendar: calendar),
            habitCount: 0,
            goalCount: 0
        )
    }

    static func weekDates(
        endingAt now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: -6 + $0, to: today) }
    }

    static func eventsByDay(
        weekDates: [Date],
        calendarEvents: [CalendarEvent],
        todos: [TodoItem],
        calendar: Calendar = .current
    ) -> [Date: [CalendarEvent]] {
        let weekDays = weekDates.map { calendar.startOfDay(for: $0) }
        let todoEventIDs = Set(todos.compactMap { $0.googleEventId })

        return calendarEvents.reduce(into: [:]) { result, event in
            guard !todoEventIDs.contains(event.id) else { return }

            for day in weekDays where eventOccurs(event, on: day, calendar: calendar) {
                result[day, default: []].append(event)
            }
        }
    }

    static func make(
        weekDates: [Date],
        eventsByDay: [Date: [CalendarEvent]],
        todos: [TodoItem],
        reminders: [TodoItem],
        historyEvents: [CalendarEvent],
        completedEventIDs: Set<String>,
        habits: [Habit],
        goals: [ChatGoal],
        now: Date = Date(),
        calendar: Calendar = .current,
        weeklyCompletionBuilder: (
            _ weekDates: [Date],
            _ eventsByDay: [Date: [CalendarEvent]],
            _ todos: [TodoItem],
            _ reminders: [TodoItem],
            _ completedEventIDs: Set<String>,
            _ calendar: Calendar
        ) -> [DayCompletion] = makeWeeklyCompletion,
        todoGrassStatsBuilder: (
            _ todos: [TodoItem],
            _ reminders: [TodoItem],
            _ historyEvents: [CalendarEvent],
            _ completedEventIDs: Set<String>,
            _ now: Date,
            _ calendar: Calendar
        ) -> TodoGrassStats = { todos, reminders, historyEvents, completedEventIDs, now, calendar in
            TodoGrassStats.make(
                todos: todos,
                reminders: reminders,
                calendarEvents: historyEvents,
                completedEventIDs: completedEventIDs,
                now: now,
                calendar: calendar
            )
        }
    ) -> ReviewMetricsSnapshot {
        ReviewMetricsSnapshot(
            weeklyCompletion: weeklyCompletionBuilder(
                weekDates,
                normalizeEventsByDay(eventsByDay, calendar: calendar),
                todos,
                reminders,
                completedEventIDs,
                calendar
            ),
            todoGrassStats: todoGrassStatsBuilder(
                todos,
                reminders,
                historyEvents,
                completedEventIDs,
                now,
                calendar
            ),
            habitCount: habits.count,
            goalCount: goals.count
        )
    }

    private static func makeWeeklyCompletion(
        weekDates: [Date],
        eventsByDay: [Date: [CalendarEvent]],
        todos: [TodoItem],
        reminders: [TodoItem],
        completedEventIDs: Set<String>,
        calendar: Calendar
    ) -> [DayCompletion] {
        let todoCounts = countTodosByDay(todos + reminders, calendar: calendar)

        return weekDates.map { date in
            let day = calendar.startOfDay(for: date)
            let events = eventsByDay[day] ?? []
            let todos = todoCounts[day] ?? (done: 0, total: 0)
            let doneEvents = events.filter { completedEventIDs.contains($0.id) }.count

            return DayCompletion(
                date: day,
                done: doneEvents + todos.done,
                total: events.count + todos.total
            )
        }
    }

    private static func countTodosByDay(
        _ todos: [TodoItem],
        calendar: Calendar
    ) -> [Date: (done: Int, total: Int)] {
        todos.reduce(into: [:]) { result, todo in
            let day = calendar.startOfDay(for: todo.date)
            var counts = result[day] ?? (done: 0, total: 0)
            counts.total += 1
            if todo.isCompleted {
                counts.done += 1
            }
            result[day] = counts
        }
    }

    private static func normalizeEventsByDay(
        _ eventsByDay: [Date: [CalendarEvent]],
        calendar: Calendar
    ) -> [Date: [CalendarEvent]] {
        eventsByDay.reduce(into: [:]) { result, entry in
            let day = calendar.startOfDay(for: entry.key)
            result[day] = entry.value
        }
    }

    private static func eventOccurs(
        _ event: CalendarEvent,
        on day: Date,
        calendar: Calendar
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        if event.isAllDay {
            let eventStart = calendar.startOfDay(for: event.startDate)
            let eventEnd = calendar.startOfDay(for: event.endDate)
            return dayStart >= eventStart && dayStart < eventEnd
        }

        return event.startDate < dayEnd && event.endDate > dayStart
    }
}

private extension ReviewMetricsSnapshot.InputSignature.TodoKey {
    init(todo: TodoItem, calendar: Calendar) {
        self.init(
            id: todo.id,
            day: calendar.startOfDay(for: todo.date),
            isCompleted: todo.isCompleted,
            googleEventId: todo.googleEventId,
            source: todo.source.rawValue,
            appleReminderIdentifier: todo.appleReminderIdentifier
        )
    }
}

private extension ReviewMetricsSnapshot.InputSignature.EventKey {
    init(event: CalendarEvent) {
        self.init(
            id: event.id,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay
        )
    }
}

private extension ReviewMetricsSnapshot.InputSignature.HabitKey {
    init(habit: Habit) {
        self.init(
            id: habit.id,
            weeklyTarget: habit.weeklyTarget,
            completedDates: Set(habit.completedDates),
            startDateKey: habit.startDateKey,
            endDateKey: habit.endDateKey
        )
    }
}
