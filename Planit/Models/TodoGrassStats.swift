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
        let allTodos = todos + reminders
        let todoEventIDSet = Set(todos.compactMap { $0.googleEventId })

        let days: [TodoGrassDay] = (0..<365).reversed().map { offset in
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
