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

    static func make(todos: [TodoItem], reminders: [TodoItem]) -> TodoGrassStats {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let all = todos + reminders

        let days: [TodoGrassDay] = (0..<30).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            let dayItems = all.filter { cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: date) }
            return TodoGrassDay(date: date, done: dayItems.filter(\.isCompleted).count, total: dayItems.count)
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
