import Foundation

struct TodoGrassDay: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let done: Int
    let total: Int
    var rate: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

struct TodoGrassStats: Equatable {
    private struct DayCounts {
        var done = 0
        var total = 0

        mutating func add(isDone: Bool) {
            total += 1
            if isDone {
                done += 1
            }
        }
    }

    let days: [TodoGrassDay]
    let weeks: [[TodoGrassDay?]]
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
        let firstDay = cal.date(byAdding: .day, value: -364, to: today) ?? today
        let allTodos = todos + reminders
        let todoEventIDSet = Set(todos.compactMap { $0.googleEventId })
        var countsByDay: [Date: DayCounts] = [:]

        for todo in allTodos {
            let day = cal.startOfDay(for: todo.date)
            guard day >= firstDay, day <= today else { continue }
            countsByDay[day, default: DayCounts()].add(isDone: todo.isCompleted)
        }

        for event in calendarEvents {
            guard !todoEventIDSet.contains(event.id) else { continue }
            let day = cal.startOfDay(for: event.startDate)
            guard day >= firstDay, day <= today else { continue }
            countsByDay[day, default: DayCounts()].add(isDone: completedEventIDs.contains(event.id))
        }

        let days: [TodoGrassDay] = (0..<365).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            let counts = countsByDay[date] ?? DayCounts()
            return TodoGrassDay(date: date, done: counts.done, total: counts.total)
        }
        let weeks = Self.makeWeeks(days: days, today: today, calendar: cal)

        var streak = 0
        for day in days.reversed() {
            guard day.total > 0, day.done == day.total else { break }
            streak += 1
        }

        return TodoGrassStats(
            days: days,
            weeks: weeks,
            totalDone: days.reduce(0) { $0 + $1.done },
            totalTodos: days.reduce(0) { $0 + $1.total },
            maxDoneInDay: days.map(\.done).max() ?? 0,
            maxTotalInDay: days.map(\.total).max() ?? 0,
            currentFullCompletionStreak: streak
        )
    }

    private static func makeWeeks(
        days: [TodoGrassDay],
        today: Date,
        calendar: Calendar
    ) -> [[TodoGrassDay?]] {
        guard let firstDay = days.first?.date else { return [] }

        let cal = calendar
        let firstDate = cal.startOfDay(for: firstDay)
        let todayStart = cal.startOfDay(for: today)
        let dayByDate = Dictionary(uniqueKeysWithValues: days.map { (cal.startOfDay(for: $0.date), $0) })
        let startOfFirstWeek = startOfWeek(containing: firstDate, calendar: cal)
        let startOfThisWeek = startOfWeek(containing: todayStart, calendar: cal)
        let totalDays = (cal.dateComponents([.day], from: startOfFirstWeek, to: startOfThisWeek).day ?? 0) + 7
        let totalWeeks = max(1, (totalDays + 6) / 7)

        return (0..<totalWeeks).map { weekOffset in
            let weekStart = cal.date(byAdding: .day, value: weekOffset * 7, to: startOfFirstWeek) ?? startOfFirstWeek
            return (0..<7).map { dayOffset in
                let date = cal.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
                let startOfDate = cal.startOfDay(for: date)
                guard startOfDate >= firstDate, startOfDate <= todayStart else { return nil }
                return dayByDate[startOfDate]
            }
        }
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: date) ?? date
    }
}
