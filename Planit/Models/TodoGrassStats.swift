import Foundation

struct TodoGrassDay: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let done: Int
    let total: Int
    var rate: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

struct TodoGrassStats: Equatable {
    let days: [TodoGrassDay]
    let totalDone: Int
    let totalTodos: Int
    let maxDoneInDay: Int
    let maxTotalInDay: Int
    let currentFullCompletionStreak: Int

    static func make(
        todos: [TodoItem],
        reminders: [TodoItem],
        calendarEvents: [CalendarEvent] = [],
        completedEventIDs: Set<String> = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodoGrassStats {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let allTodos = todos + reminders
        let todoEventIDSet = Set(todos.compactMap { $0.googleEventId })

        let days: [TodoGrassDay] = (0..<30).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            guard let interval = cal.dateInterval(of: .day, for: date) else {
                return TodoGrassDay(date: date, done: 0, total: 0)
            }

            let dayTodos = allTodos.filter {
                cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: date)
            }
            let dayEvents = calendarEvents.filter { ev in
                !todoEventIDSet.contains(ev.id) &&
                ev.startDate >= interval.start && ev.startDate < interval.end
            }

            let doneTodos = dayTodos.filter(\.isCompleted).count
            let doneEvents = dayEvents.filter { completedEventIDs.contains($0.id) }.count
            let totalTodos = dayTodos.count + dayEvents.count
            let totalDone = doneTodos + doneEvents

            return TodoGrassDay(date: date, done: totalDone, total: totalTodos)
        }

        var streak = 0
        for day in days.reversed() {
            guard day.total > 0, day.done == day.total else { break }
            streak += 1
        }

        return TodoGrassStats(
            days: days,
            totalDone: days.reduce(0) { $0 + $1.done },
            totalTodos: days.reduce(0) { $0 + $1.total },
            maxDoneInDay: days.map(\.done).max() ?? 0,
            maxTotalInDay: days.map(\.total).max() ?? 0,
            currentFullCompletionStreak: streak
        )
    }
}
