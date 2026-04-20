import Foundation

struct TodoGrassDay: Identifiable, Equatable {
    let date: Date
    let done: Int
    let total: Int

    var id: Date { date }
    var rate: Double { total > 0 ? Double(done) / Double(total) : 0 }
    var isFullyComplete: Bool { total > 0 && done == total }
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
        now: Date = Date(),
        calendar inputCalendar: Calendar = .current
    ) -> TodoGrassStats {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let allTodos = todos + reminders

        let days: [TodoGrassDay] = (0..<30).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let interval = calendar.dateInterval(of: .day, for: day) else {
                return nil
            }
            let scheduled = allTodos.filter {
                $0.date >= interval.start && $0.date < interval.end
            }
            let done = scheduled.filter(\.isCompleted).count
            return TodoGrassDay(date: interval.start, done: done, total: scheduled.count)
        }

        let totalDone = days.reduce(0) { $0 + $1.done }
        let totalTodos = days.reduce(0) { $0 + $1.total }
        let maxDay = days.max {
            if $0.done != $1.done { return $0.done < $1.done }
            return $0.total < $1.total
        }

        var streak = 0
        for day in days.reversed() {
            guard day.isFullyComplete else { break }
            streak += 1
        }

        return TodoGrassStats(
            days: days,
            totalDone: totalDone,
            totalTodos: totalTodos,
            maxDoneInDay: maxDay?.done ?? 0,
            maxTotalInDay: maxDay?.total ?? 0,
            currentFullCompletionStreak: streak
        )
    }
}
